# Deployment Architecture Review — Free Tier Optimization

## Current architecture (as built)
```
AWS Paid MVP (ECS 24×7 + RDS 24×7) = ~$35/mo
```

## Your use case
- **Budget**: AWS free tier credits until April 30
- **Traffic**: <10 requests/day (test/demo phase)
- **Goal**: Validate product, not run production

---

## Problem: Current design is PAID

| Service | Your usage | Free tier | Status |
|---------|-----------|-----------|--------|
| ECS Fargate | 730 hrs/mo (24×7) | 100 hrs/mo | **PAID** ($18/mo) |
| RDS micro | 730 hrs/mo (24×7) | 750 hrs/mo | **Barely free** (~$1–2/mo overage) |
| Ollama model | ~15 GB downloaded | Not free | **PAID** (data transfer) |
| CloudFront + S3 | Low traffic | 1 TB free | ✓ Free |
| Fargate storage (ephemeral) | 30 GB | Free | ✓ Free |

**You'll exhaust free credits in 10–14 days on ECS alone.**

---

## Recommended: Hybrid free-tier design

Switch from **"always-on"** to **"on-demand"** compute.

### Option A: AWS Lambda + API Gateway (Recommended for MVP)

**Architecture:**
```
React Web (CloudFront + S3)  ──┐
React Native (Expo)           ├──→ API Gateway (HTTP + WebSocket)
                              │         │
                              │         ├─→ Lambda@Edge (auth, routing)
                              │         │
                              │         ├─→ Lambda (chat handler, 1GB, 1 min timeout)
                              │               ├─ Call Ollama on EC2 / ECS spot
                              │               └─ RDS read/write
                              │
RDS Aurora micro (MySQL)      ←─ Shared managed database
ECS Spot 4 GB (Ollama only)   ←─ Ollama inference server (turned off when idle)
```

**Free tier components:**
- **Lambda**: 1M requests/month free + 400,000 GB-seconds (your traffic = ~480 GB-sec/mo = **free**)
- **API Gateway**: 1M requests/month free (your ~10 req/day = **free**)
- **RDS Aurora Serverless v2**: Pay-per-second, auto-pause after 5 min (your idle = **~$1/mo**)
- **EC2 / ECS Spot**: Turned OFF except during requests (~$0.01/request for warmup)
- **CloudFront + S3**: **free**

**Total: ~$3–5/mo instead of $35/mo.**

**Tradeoff:**
- Cold start (3–5 seconds first time, then warm for 15 min) — acceptable for MVP
- Ollama runs on separate Spot instance (no sidecar); Lambda calls it via HTTP
- No stateful connection (WebSocket would require ALB or AppSync, both paid)

---

### Option B: EC2 Spot + RDS free tier (if you want full control)

**Architecture:**
```
React Web (CloudFront + S3)  ──────┐
React Native                       ├──→ Route53 A record
                                   │
                    EC2 t3.micro Spot instance (backend + Ollama sidecar)
                    • 24×7 run: $2–3/mo (Spot savings)
                    • Same Docker image as ECS
                    • Manual SSH startup/stop script
                    │
                    └──→ RDS Postgres micro (single-AZ, 750 hrs free)
```

**Free tier components:**
- **EC2 t3.micro Spot**: 10–90% discount = **$1–3/mo instead of $12**
- **RDS Postgres**: 750 hrs/mo, 20 GB free = **free**
- **Route53**: ~$0.50/mo (very cheap; skip if you use IP address)
- **CloudFront + S3**: **free**

**Total: ~$5–8/mo.**

**Tradeoff:**
- Less managed; you own the OS (patching, monitoring)
- Spot interruption risk (rare, but tolerable for test env)
- Auto-recovery requires an Elastic IP (~$3.25/mo) if you want persistent DNS
- Manual scale-down when not testing

---

## Comparison: All three options

| Aspect | Current (ECS 24×7) | **Option A (Lambda)** | **Option B (EC2 Spot)** |
|--------|-------------------|-------------------|-------------------|
| **Monthly cost (free tier)** | $35 → $0 credits exhausted in 10d | $3–5 ✓ | $5–8 ✓ |
| **Cold start latency** | ~500 ms | **3–5 sec** | ~500 ms |
| **Warmth guarantee** | Always hot | 15 min idle timeout | Always hot (if running) |
| **Ops complexity** | Medium (ECS, Fargate) | Low (serverless) | Low–Medium (EC2 management) |
| **Ollama inference speed** | Sidecar (fast) | Separate instance (HTTP RPC) | Sidecar (fast) |
| **Suitable for testing?** | Yes, but expensive | **Yes, best for MVP** | Yes, good middle ground |
| **Path to production** | Already prod-ready | Needs WebSocket → AppSync | Already prod-ready |

---

## My recommendation: **Option A (Lambda) for April sprint**

### Why:
1. **Stay under $5/mo** — you'll have credits left over
2. **Zero ops** — no instances to manage or SSH into
3. **Auto-scale to zero** — not paying for idle time
4. **Pay only for what you use** — 10 req/day = 5–10 sec compute/day
5. **Smooth migration** — when traffic grows, move to ECS (same Docker image)

### Implementation (2–3 hours):
1. Rewrite `ChatController` to be Lambda-native (use Spring Cloud Function, or raw handler)
2. Deploy to Lambda via SAM or Terraform
3. API Gateway in front (auto-provisioned)
4. Ollama on **separate, always-off EC2 Spot** instance or **Lambda container image** with ephemeral storage
5. RDS Aurora Serverless v2 (auto-pause, pay-per-sec)

---

## Short-term (April 30): Minimal changes needed

**Keep the current Terraform but modify:**

### `terraform/ecs.tf` → `terraform/lambda.tf`
Replace ECS task with Lambda function definition:
```hcl
resource "aws_lambda_function" "chat" {
  filename      = "backend/target/chat-lambda.jar"  # Spring Cloud Function packaging
  function_name = "homeo-ai-chat"
  role          = aws_iam_role.lambda.arn
  handler       = "org.springframework.cloud.function.adapter.aws.FunctionInvoker"
  runtime       = "java21"
  timeout       = 60
  memory_size   = 1024

  environment {
    variables = {
      DB_URL = "jdbc:postgresql://${aws_rds_cluster_instance.aurora.endpoint}:5432/homeo"
      OLLAMA_URL = "http://${aws_instance.ollama_spot.private_ip}:11434"
      # ... other vars
    }
  }
}

resource "aws_apigatewayv2_api" "http" {
  name          = "homeo-ai"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_integration" "lambda" {
  api_id           = aws_apigatewayv2_api.http.id
  integration_type = "AWS_PROXY"
  integration_uri  = aws_lambda_function.chat.invoke_arn
}
```

### `terraform/rds.tf` → Aurora Serverless v2
```hcl
resource "aws_rds_cluster" "aurora" {
  cluster_identifier      = "homeo-aurora"
  engine                  = "aurora-postgresql"
  engine_version          = "16.1"
  database_name           = "homeo"
  master_username         = "homeo"
  master_password         = var.db_password
  db_subnet_group_name    = aws_db_subnet_group.main.name
  vpc_security_group_ids  = [aws_security_group.db.id]
  skip_final_snapshot     = true

  # Serverless v2: auto-pause, auto-scale
  serverlessv2_scaling_configuration {
    max_capacity = 0.5  # $0.06/hour when running
    min_capacity = 0.5
  }

  enable_http_endpoint = true  # allows Data API (optional)
}
```

### `terraform/ec2.tf` (new) → Ollama on Spot
```hcl
resource "aws_instance" "ollama" {
  ami                 = "ami-0c55b159cbfafe1f0"  # Amazon Linux 2
  instance_type       = "t3.medium"  # Can run Ollama
  key_name            = aws_key_pair.admin.key_name
  subnet_id           = aws_subnet.public[0].id
  iam_instance_profile = aws_iam_instance_profile.ec2.name

  # Spot instance (70% cheaper)
  instance_market_options {
    market_type = "spot"
  }

  # Auto-stop on shutdown to save money
  disable_api_termination = false

  # User data: install Ollama + pull models (runs once)
  user_data = base64encode(templatefile("${path.module}/ollama_setup.sh", {
    model = var.ollama_model
  }))

  tags = { Name = "${var.project}-ollama" }
}
```

---

## Revised cost estimate (April 30)

| Item | Hourly | Monthly (730 hrs) | Free tier | **Actual cost** |
|------|--------|-----------|-----------|---|
| Lambda (10 req/day) | $0 | $0 | 1M req free | **$0** |
| API Gateway (10 req/day) | $0 | $0 | 1M req free | **$0** |
| Aurora Serverless v2 (idle 23 hrs/day) | $0.06 | ~$2–3 | None | **$2–3** |
| EC2 t3.medium Spot (always off) | $0.002–0.004 | $1–3 | 750 hrs t2.micro free | **$0** (if you use manual on/off) |
| Data transfer (inference calls) | Negligible | <$1 | 1 GB free | **<$1** |
| CloudFront + S3 + CloudWatch | Negligible | <$1 | 1 TB free | **$0** |
| **TOTAL** | | | | **$2–4/mo** |

**Remaining free credits: $350+ (if you had $100/mo free tier).**

---

## Migration path (April 30 → May 1)

**Week of April 30:**
- Load test the Lambda + Aurora + Spot architecture
- Fix any cold-start pain points
- Cost is stable at $2–5/mo

**May 1–30:**
- If you want to grow past 100 req/day, migrate to ECS (already built)
- ECS will cost $35/mo but handle 10,000 req/day with no changes
- Same Docker image, same Spring Boot code, same DB schema

---

## Decision Matrix

**Pick Option A (Lambda) if:**
- ✓ You want to stay free until May 1
- ✓ You're OK with 3–5 sec cold start (acceptable for intake chatbot)
- ✓ You want zero ops burden
- ✓ You want to test the product first, scale later

**Pick Option B (EC2 Spot) if:**
- ✓ You want to avoid cold start (users expect <1 sec response)
- ✓ You're willing to manage SSH, OS patching
- ✓ You want to save $1–2/mo vs. Lambda (not worth it for MVP)

**Stick with Option current (ECS 24×7) if:**
- ✓ You're already past April 30 (credits are spent anyway)
- ✓ You want production-grade Fargate from day one
- ✓ You're planning to deploy to production immediately

---

## Action items for you

1. **Choose an option** (I recommend Lambda)
2. **I'll rewrite Terraform** to implement it
3. **Modify ChatController** to be Lambda-native (Spring Cloud Function wrapper)
4. **Update Dockerfile** for Lambda container runtime
5. **Test locally** with SAM CLI
6. **Deploy via `terraform apply`**

Want me to proceed with **Option A (Lambda rewrite)**, or do you have questions?
