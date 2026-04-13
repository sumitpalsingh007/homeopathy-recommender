# Homeo AI — Agentic Homeopathic Intake Chatbot

A production-ready MVP combining **Spring AI 1.0** + **Ollama** + **pgvector**, deployed on AWS for **~$3–5/mo**.

---

## 🚀 Quick start (pick your path)

### I want to test locally (5 min)
→ Read: [`QUICK_START.md`](QUICK_START.md) section 1

```bash
docker-compose up -d
open http://localhost:5173
```

### I want to deploy to AWS (20 min)
→ Read: [`QUICK_START.md`](QUICK_START.md) section 2

```bash
cd terraform
terraform apply -var="db_password=..." -var="jwt_secret=..."
```

### I want to understand the architecture
→ Read: [`DEPLOYMENT_REVIEW.md`](DEPLOYMENT_REVIEW.md)

### I'm debugging something
→ Read: [`OPS_GUIDE.md`](OPS_GUIDE.md)

### I want the full deployment playbook
→ Read: [`DEPLOYMENT_RUNBOOK.md`](DEPLOYMENT_RUNBOOK.md)

---

## 📚 Documentation roadmap

| Document | Purpose | Read time |
|----------|---------|-----------|
| **[QUICK_START.md](QUICK_START.md)** | Local test + AWS deploy in 20 min | 5 min |
| **[DEPLOYMENT_SUMMARY.md](DEPLOYMENT_SUMMARY.md)** | What you have, checklist, FAQs | 10 min |
| **[DEPLOYMENT_REVIEW.md](DEPLOYMENT_REVIEW.md)** | Architecture decisions explained | 10 min |
| **[EC2_SPOT_VS_ONDEMAND.md](EC2_SPOT_VS_ONDEMAND.md)** | Cost analysis, Spot interruption reality | 5 min |
| **[DEPLOYMENT_RUNBOOK.md](DEPLOYMENT_RUNBOOK.md)** | Detailed step-by-step + troubleshooting | 15 min |
| **[OPS_GUIDE.md](OPS_GUIDE.md)** | Monitoring, debugging, backup, scaling | 10 min |

---

## 🏗️ Project structure

```
homeopathy-scraper/
├── backend/                  # Spring Boot API
│   ├── src/main/java/
│   │   └── com/homeo/ai/
│   │       ├── config/       # Spring AI ChatClient config
│   │       ├── agent/        # @Tool methods (searchMedicines, etc)
│   │       ├── chat/         # ChatController, ConsultationService
│   │       ├── medicine/     # MedicineEntity, Repository
│   │       ├── patient/      # PatientEntity, ConsultationEntity
│   │       ├── security/     # JWT, AuthController
│   │       └── rag/          # IngestionRunner (CSV → vector store)
│   ├── Dockerfile            # Docker build
│   └── pom.xml               # Maven dependencies
├── web/                      # React web UI
│   ├── src/
│   │   ├── main.jsx          # Router setup
│   │   ├── App.jsx           # Main layout
│   │   ├── Login.jsx         # Auth
│   │   ├── Chat.jsx          # Chat interface
│   │   └── api.js            # Axios client
│   ├── package.json
│   └── vite.config.js
├── mobile/                   # React Native (Expo)
│   ├── App.js                # Router setup
│   ├── src/
│   │   ├── api.js            # Axios client
│   │   ├── LoginScreen.js    # Auth
│   │   └── ChatScreen.js     # Chat interface
│   └── package.json
├── terraform/                # Infrastructure as Code
│   ├── versions.tf           # Terraform config
│   ├── variables.tf          # Input variables
│   ├── network.tf            # VPC, subnets, security groups
│   ├── rds.tf                # RDS Postgres + pgvector
│   ├── ec2_asg.tf            # EC2 Spot + ASG (auto-recovery)
│   ├── web.tf                # S3 + CloudFront
│   ├── outputs.tf            # Output values
│   └── user_data.sh          # EC2 startup script
├── sql/                      # Database scripts
│   ├── 01_bootstrap.sql      # User & DB creation
│   ├── 02_schema.sql         # Tables & indexes
│   └── 03_load_csv.sql       # Data loading
├── .github/workflows/        # CI/CD pipelines
│   ├── backend.yml           # Maven → Docker → ECR → ECS
│   ├── web.yml               # Vite → S3 → CloudFront
│   ├── mobile.yml            # EAS build
│   └── terraform.yml         # Terraform plan & apply
├── docker-compose.yml        # Local dev environment
├── QUICK_START.md            # 5-min local test, 15-min AWS deploy
├── DEPLOYMENT_SUMMARY.md     # High-level overview & checklist
├── DEPLOYMENT_REVIEW.md      # Architecture decisions explained
├── DEPLOYMENT_RUNBOOK.md     # Detailed deployment guide
├── OPS_GUIDE.md              # Monitoring, debugging, recovery
└── EC2_SPOT_VS_ONDEMAND.md   # Cost analysis
```

---

## 💰 Cost (April 1–30, free tier)

| Component | Usage | Cost |
|-----------|-------|------|
| EC2 t3.micro Spot | 24×7 | $0 (free tier 750 hrs) |
| RDS Postgres micro | 24×7 | $2–3 (750 hrs free, slight overage) |
| CloudFront + S3 | Low traffic | $0 (1 TB free) |
| Other (logs, etc) | Minimal | <$1 |
| **TOTAL** | | **$2–5/mo** |

**After May 1:** Same cost ($2–5/mo) unless you scale up.

---

## 🎯 What you get

### Backend (Spring Boot)
- ✅ Spring AI 1.0 `ChatClient` with agentic tool calling
- ✅ RAG via pgvector (Allen + Kent rubrics)
- ✅ JWT auth + patient management
- ✅ Ollama integration (self-hosted LLM)
- ✅ Flyway migrations
- ✅ Docker image (ready to push to ECR or Docker Hub)

### Frontend
- ✅ React web UI (Vite, responsive)
- ✅ React Native mobile app (Expo)
- ✅ Both consume same `/api/chat` endpoint

### Infrastructure
- ✅ **EC2 Spot t3.micro + ASG** (auto-recovery, $2–3/mo)
- ✅ RDS Postgres 16 + pgvector ($2–3/mo)
- ✅ CloudFront + S3 (static web, $0–1/mo)
- ✅ VPC with security groups (no NAT GW = cost savings)
- ✅ CloudWatch logs, IAM roles, alarms

### Deployment
- ✅ Terraform (complete infrastructure as code)
- ✅ GitHub Actions (CI/CD pipelines)
- ✅ Docker Compose (local testing)

### Documentation
- ✅ 6 comprehensive guides (architecture, deployment, ops, troubleshooting)

---

## 🔧 Key decisions (architecture review)

| Decision | Why | Alternative |
|----------|-----|-------------|
| **EC2 Spot (not Lambda)** | No 5+ sec cold start; demo-friendly | Lambda ($2–5/mo, but cold start) |
| **ASG with capacity rebalance** | Auto-recovery from Spot interrupt | Manual recovery, or on-demand ($12/mo) |
| **Ollama (not Bedrock)** | Self-hosted, no API costs, full control | AWS Bedrock (managed, costs more) |
| **PGVector (not OpenSearch)** | Included in Postgres, cheaper | OpenSearch ($175+/mo) |
| **Spot t3.micro (not larger)** | Minimal cost during testing | t3.small ($8/mo), t3.medium ($20/mo) |
| **No NAT GW** | Saves $30/mo | With NAT: $30/mo extra |

See [`DEPLOYMENT_REVIEW.md`](DEPLOYMENT_REVIEW.md) for full analysis.

---

## 🚨 Known limitations (and how to fix them)

| Issue | Workaround |
|-------|-----------|
| Spot instance can interrupt 1–2x/month | ASG auto-recovers within 2–3 min; acceptable for MVP |
| Cold start (first Ollama inference): 5+ sec | Warm-up script before demoing; or use larger instance |
| First request takes 2–3 sec (Spring + Ollama) | Normal for agentic LLM; acceptable for intake chatbot |
| RDS slightly over free tier | Cost: $2–3/mo; acceptable for MVP |

None of these are blockers. They're MVP tradeoffs.

---

## 📈 Scaling path (May 1+)

**Light growth (100–1000 req/day):**
1. Keep EC2 Spot, increase to `t3.small` → $5–8/mo
2. Add ALB + 2–3 instances → $25–30/mo total
3. Same Spring Boot code, same RDS, same frontend

**Heavy growth (>1000 req/day):**
1. Migrate to ECS Fargate → $35+/mo
2. Scale horizontally with no code changes
3. Add managed services (ElastiCache, OpenSearch) as needed

**All paths:**
- Same Docker image
- Same Terraform code (just swap `ec2_asg.tf` → `fargate.tf`)
- No application rewrites

---

## 🎓 Learning outcomes

### Latest Java/Spring AI features demonstrated
- **Spring AI 1.0 ChatClient** (fluent API, advisors)
- **Agentic tool calling** (`@Tool` methods)
- **RAG with PgVectorStore** (HNSW + cosine)
- **Chat memory advisor** (multi-turn sessions)
- **Reactive streaming** (`/api/chat/stream`)
- **Ollama auto-configuration** (swappable LLM)

### AWS best practices
- Infrastructure as code (Terraform)
- Cost optimization (free tier, Spot instances, ASG)
- Auto-recovery (capacity rebalancing)
- Monitoring (CloudWatch)
- Security (security groups, IAM, JWT)

---

## 🆘 Help

**First time deploying?** → Read [`QUICK_START.md`](QUICK_START.md)

**Something broke?** → Check [`DEPLOYMENT_RUNBOOK.md`](DEPLOYMENT_RUNBOOK.md) troubleshooting

**Want to understand architecture?** → Read [`DEPLOYMENT_REVIEW.md`](DEPLOYMENT_REVIEW.md)

**Debugging an issue?** → Check [`OPS_GUIDE.md`](OPS_GUIDE.md)

---

## 📝 Medicine data

This project ships with:
- **Allen's Keynotes**: 183 medicines
- **Kent's Repertory**: 222,000 rubric entries (22 chapters)
- **Kent's Lectures**: 180 medicines (materia medica)
- **Master index**: 654 unified medicines across all sources

Data is loaded into:
- Relational DB (medicine table for quick lookup)
- Vector store (pgvector for RAG)

See `src/main/resources/` for CSVs.

---

## 📄 License

This is a sample project demonstrating Spring AI + AWS deployment. Use as reference for your own projects.

---

## 🎉 Ready?

1. **Local test**: `docker-compose up -d` (QUICK_START.md section 1)
2. **AWS deploy**: `terraform apply` (QUICK_START.md section 2)
3. **Demo**: Share the CloudFront URL with anyone

Let's build! 🚀
