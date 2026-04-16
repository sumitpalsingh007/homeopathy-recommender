# Deployment Runbook — Homeo AI MVP

## Architecture

```
React Web (CloudFront + S3)  ─┐
React Native (Expo)           ├──→ Security Group (port 8080)
                              │
                    EC2 t3.micro Spot instance (ASG)
                    ├─ Spring Boot backend (port 8080)
                    └─ Ollama sidecar (port 11434, internal)
                             │
                             └──→ RDS Postgres 16 + pgvector
```

**Cost: ~$2–5/mo (free tier eligible through May 1)**

---

## Prerequisites

1. **AWS Account** with free tier credits
2. **Terraform >= 1.9.5**
3. **AWS CLI v2** configured with credentials
4. **Docker** (for local testing)
5. **Git** (to clone the repo)

---

## Phase 1: Local Testing (do this first!)

### 1.1 Start local stack

```bash
cd homeopathy-recommender

# Copy medicine CSV to backend
cp src/main/resources/medicine_master.csv backend/src/main/resources/

# Start all services
docker-compose up -d

# Wait for services to be ready (~30 sec for Ollama model download)
docker-compose logs -f backend
```

Expected output:
```
backend  | 2026-04-10 12:34:56 INFO: Started HomeoAiApplication in 15.234 seconds
```

### 1.2 Test the stack

```bash
# 1. Create a test user
curl -X POST http://localhost:8080/api/auth/signup \
  -H "Content-Type: application/json" \
  -d '{
    "email": "test@example.com",
    "password": "testpassword123",
    "fullName": "Test User",
    "age": 30,
    "sex": "M"
  }'

# Save the token from response
TOKEN="<token-from-response>"

# 2. Chat with the bot
curl -X POST http://localhost:8080/api/chat \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "message": "I have a headache",
    "sessionId": null
  }'

# Expected: Response from Dr. Samuel asking clarifying questions
```

### 1.3 Test the web UI

Open http://localhost:5173 in your browser.

1. Sign up with test@example.com / testpassword123
2. Chat with the bot
3. Verify responses come back in 2–3 seconds

### 1.4 Teardown

```bash
docker-compose down
docker-compose down -v  # Remove volumes if you want a clean slate
```

---

## Phase 2: Deploy to AWS (with Terraform)

### 2.1 Set up Terraform state S3 bucket

**First time only:**

```bash
cd terraform

# Create S3 bucket for Terraform state (must be globally unique)
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
STATE_BUCKET="homeo-ai-tfstate-${ACCOUNT_ID}"

aws s3api create-bucket \
  --bucket "$STATE_BUCKET" \
  --region ap-south-1 \
  --create-bucket-configuration LocationConstraint=ap-south-1

# Enable versioning
aws s3api put-bucket-versioning \
  --bucket "$STATE_BUCKET" \
  --versioning-configuration Status=Enabled

# Block public access
aws s3api put-public-access-block \
  --bucket "$STATE_BUCKET" \
  --public-access-block-configuration \
  "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"
```

Update `versions.tf` with your bucket name:
```hcl
backend "s3" {
  bucket = "homeo-ai-tfstate-123456789012"  # Use actual account ID
  key    = "mvp/terraform.tfstate"
  region = "ap-south-1"
}
```

### 2.2 Initialize Terraform

```bash
terraform init
```

### 2.3 Plan the deployment

```bash
# Generate strong passwords
DB_PASSWORD=$(openssl rand -base64 16)
JWT_SECRET=$(openssl rand -base64 32)

echo "DB_PASSWORD: $DB_PASSWORD"
echo "JWT_SECRET: $JWT_SECRET"

# Plan (preview changes)
terraform plan \
  -var="db_password=$DB_PASSWORD" \
  -var="jwt_secret=$JWT_SECRET" \
  -out=tfplan
```

Review the plan output. You should see:
- VPC (1)
- Subnets (2)
- Security groups (2)
- RDS instance (1)
- Launch template (1)
- ASG (1)
- S3 bucket (1)
- CloudFront distribution (1)
- IAM roles (3)

**Estimated cost: $2–5/mo**

### 2.4 Apply

```bash
terraform apply tfplan
```

This takes **5–10 minutes**. Terraform will:
1. Create VPC + subnets
2. Launch RDS Postgres (takes longest, ~5 min)
3. Create ASG + launch template
4. Launch first EC2 Spot instance
5. Run user_data.sh (Docker setup + model download, ~10 min inside instance)
6. Create S3 bucket + CloudFront

### 2.5 Retrieve outputs

```bash
terraform output -json > outputs.json
cat outputs.json

# You'll see:
{
  "asg_name": "homeo-ai-asg",
  "backend_log_group": "/ec2/homeo-ai-backend",
  "backend_security_group": "sg-xxxxx",
  "cloudfront_domain": "d123.cloudfront.net",
  "cloudfront_id": "EXXXXX",
  "rds_endpoint": "homeo-ai-db.xxxxx.ap-south-1.rds.amazonaws.com",
  "web_bucket": "homeo-ai-web-123456789012"
}
```

---

## Phase 3: Verify AWS deployment

### 3.1 Wait for EC2 instance to be ready

The EC2 instance needs **5–10 minutes** to pull Ollama models and start the backend.

```bash
# Monitor the instance startup
aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=homeo-ai-backend" \
  --region ap-south-1 \
  --query 'Reservations[0].Instances[0].[InstanceId,State.Name,PublicIpAddress]' \
  --output table

# Watch the logs
aws logs tail /ec2/homeo-ai-backend --follow --region ap-south-1
```

Expected logs:
```
user-data.log: === User Data: Starting homeo-ai backend + ollama ===
docker: Pulling ollama/ollama:latest
backend: Spring Boot context initialized
backend: Listening on 0.0.0.0:8080
```

### 3.2 Test the backend directly

Once logs show backend is running:

```bash
# Get the instance's public IP
INSTANCE_IP=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=homeo-ai-backend" \
  --region ap-south-1 \
  --query 'Reservations[0].Instances[0].PublicIpAddress' \
  --output text)

# Test health endpoint
curl -v http://$INSTANCE_IP:8080/actuator/health

# Expected: HTTP 200 { "status": "UP" }
```

### 3.3 Deploy the web frontend

Build the React app:

```bash
cd web
npm install
npm run build

# Upload to S3
aws s3 sync dist/ s3://$(terraform output -raw web_bucket) --delete --region ap-south-1

# Invalidate CloudFront cache
aws cloudfront create-invalidation \
  --distribution-id $(terraform output -raw cloudfront_id) \
  --paths '/*' \
  --region ap-south-1
```

### 3.4 Access the app

Open your browser to:
```
https://$(terraform output -raw cloudfront_domain)
```

(It might take 2–3 minutes for CloudFront to cache the index.html)

---

## Phase 4: Smoke tests (sanity check)

### 4.1 Sign up + login

```bash
# Get frontend URL
FRONTEND_URL="https://$(terraform output -raw cloudfront_domain)"

# Sign up
curl -X POST $FRONTEND_URL/api/auth/signup \
  -H "Content-Type: application/json" \
  -d '{
    "email": "demo@homeo-ai.app",
    "password": "DemoPassword123!",
    "fullName": "Demo User"
  }'

# Should return: { "token": "eyJ..." }
```

### 4.2 Chat

```bash
TOKEN="<token-from-signup>"

curl -X POST $FRONTEND_URL/api/chat \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "message": "I have a sudden high fever and chills",
    "sessionId": null
  }'

# Expected latency: 2–3 seconds
# Response: Dr. Samuel asking clarifying questions
```

### 4.3 Open the web UI in browser

1. Navigate to https://$(terraform output -raw cloudfront_domain)
2. Sign up
3. Chat with Dr. Samuel
4. Verify messages appear in 2–3 seconds

---

## Maintenance & troubleshooting

### Monitor Spot interruptions

```bash
# Check CloudWatch for ASG terminations
aws autoscaling describe-scaling-activities \
  --auto-scaling-group-name $(terraform output -raw asg_name) \
  --region ap-south-1 \
  --max-records 10

# Check instance health
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names $(terraform output -raw asg_name) \
  --region ap-south-1 \
  --query 'AutoScalingGroups[0].Instances'
```

### View logs

```bash
# Backend logs
aws logs tail /ec2/homeo-ai-backend --follow --region ap-south-1

# Detailed output (last 1000 lines)
aws logs get-log-events \
  --log-group-name /ec2/homeo-ai-backend \
  --log-stream-name user-data.log \
  --start-from-head \
  --region ap-south-1 \
  | jq '.events[] | .message' -r | tail -50
```

### SSH into instance (if needed)

```bash
# Get instance ID
INSTANCE_ID=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=homeo-ai-backend" \
  --region ap-south-1 \
  --query 'Reservations[0].Instances[0].InstanceId' \
  --output text)

# Use AWS Systems Manager Session Manager (no SSH key needed)
aws ssm start-session --target $INSTANCE_ID --region ap-south-1

# Inside the instance:
docker ps                          # Check running containers
docker-compose logs -f backend     # View backend logs
curl http://localhost:8080/actuator/health  # Health check
```

### Common issues

**Issue: "Connection refused" when accessing frontend**
- CloudFront caches take 2–3 min to populate
- Check S3 bucket has the built files: `aws s3 ls s3://$(terraform output -raw web_bucket)`

**Issue: "503 Service Unavailable" from backend**
- EC2 instance still pulling Ollama model (takes ~10 min first time)
- Check logs: `aws logs tail /ec2/homeo-ai-backend --follow`

**Issue: High latency (>5 sec) on first request**
- Normal: Ollama model loads into memory on first inference
- Subsequent requests should be 2–3 sec

**Issue: Instance keeps restarting (Spot interruptions)**
- Totally normal; ASG auto-replaces within 2–3 min
- Monitor: `aws autoscaling describe-scaling-activities --auto-scaling-group-name homeo-ai-asg`

---

## Cost & cleanup

### Estimated monthly cost (April 1–30)

| Component | Usage | Free tier | Cost |
|-----------|-------|-----------|------|
| EC2 Spot t3.micro | 730 hrs (24×7) | 750 hrs | $0 (within free tier) |
| RDS Postgres micro | 730 hrs + 20 GB | 750 hrs free tier | ~$2–3 |
| CloudFront + S3 | Low traffic | 1 TB free | $0 |
| CloudWatch logs | 7 days retention | Minimal | <$1 |
| **Total** | | | **$2–4/mo** |

### Destroy infrastructure (stop paying)

```bash
terraform destroy \
  -var="db_password=$DB_PASSWORD" \
  -var="jwt_secret=$JWT_SECRET"
```

This removes everything **except the S3 state bucket**. Keep the state bucket for future `terraform apply`.

---

## Next steps (after April 30)

1. **Monitor costs**: You have ~$100 free tier credits. If you hit April 30 and haven't spent them all, you're golden.
2. **Scale up**: If traffic grows past 10 req/day:
   - Increase ASG `max_size` to 2–3
   - Add an ALB (load balancer) with target group
   - Cost increases to ~$25–30/mo
3. **Move to ECS Fargate**: The Docker image is already built. Just change terraform target from EC2 to Fargate.

---

## GitHub Actions CI/CD

Once you push to GitHub, the workflows auto-trigger:

1. **backend.yml**: Builds JAR, creates Docker image, pushes to ECR
2. **web.yml**: Builds React app, syncs to S3, invalidates CloudFront
3. **mobile.yml**: (Optional) Builds iOS/Android via EAS
4. **terraform.yml**: Plans and applies infrastructure changes

For now, deploy manually. Set up GitHub Actions when you're ready to automate.

---

## Questions?

Check:
1. CloudWatch logs: `aws logs tail /ec2/homeo-ai-backend`
2. EC2 instance status: `aws ec2 describe-instances --filters Name=tag:Name,Values=homeo-ai-backend`
3. RDS connectivity: `psql -h $(terraform output -raw rds_endpoint) -U homeo -d homeo`
