# Homeo AI — Agentic MVP

Contextual homeopathic intake chatbot powered by **Spring AI 1.0** + **Ollama** + **pgvector**, React web, React Native mobile, deployed on AWS via Terraform.

## Architecture

```
React Web (CloudFront + S3) ─┐
React Native (Expo)          ├──► Spring Boot API (ECS Fargate task)
                             │        │
                             │        ├── Ollama sidecar (llama3.1:8b + nomic-embed-text)
                             │        │
                             │        └── RDS Postgres 16 + pgvector
                             │              • medicine / patient / consultation
                             │              • medicine_vectors (HNSW, cosine)
                             │
                             └──► /api/auth/**   /api/chat
```

## Agentic flow
Spring AI `ChatClient` is wired with:
1. System prompt — "Dr. Samuel" intake persona
2. `MessageChatMemoryAdvisor` — per-session conversation memory
3. `QuestionAnswerAdvisor` — RAG over pgvector (Allen + Kent rubrics)
4. `@Tool` methods (`HomeoTools`) — searchMedicines, getMedicine, getPatientHistory

The LLM autonomously decides when to call tools mid-conversation (agentic loop built into Spring AI 1.0 tool-calling).

## Deliverables in this repo
| # | Path | Contents |
|---|------|----------|
| 1 | `backend/`    | Spring Boot 3.3 + Spring AI 1.0-M3 (ChatClient, tools, PGVector, Flyway, JWT, JPA) |
| 2 | `web/`        | React 18 + Vite SPA |
| 3 | `mobile/`     | React Native (Expo) app |
| 4 | `sql/`        | Bootstrap + schema + CSV loader scripts |
| 5 | `.github/workflows/` | CI/CD for backend (ECR+ECS), web (S3+CF), mobile (EAS), terraform |
| 6 | `terraform/`  | VPC, RDS pgvector, ECR, ECS Fargate (backend+ollama), S3+CloudFront |

## Monthly cost (ap-south-1, idle MVP)
| Item | ~USD/mo |
|---|---|
| RDS db.t4g.micro + 20GB gp3 | 14 |
| ECS Fargate 1 vCPU / 3 GB 24×7 | 18 |
| ECR + S3 + CloudWatch logs | 2 |
| CloudFront + S3 web | 1–2 |
| **Total** | **~35–36** |

No NAT GW. No ALB. No Bedrock. Shut the ECS service down when not in use to drop to ~$16/mo.

## Local dev
```bash
# 1. Postgres with pgvector
docker run -d --name pg -e POSTGRES_PASSWORD=homeo -e POSTGRES_USER=homeo -e POSTGRES_DB=homeo -p 5432:5432 pgvector/pgvector:pg16

# 2. Ollama
docker run -d --name ollama -p 11434:11434 ollama/ollama
docker exec ollama ollama pull llama3.1:8b-instruct-q4_0
docker exec ollama ollama pull nomic-embed-text

# 3. Backend
cp src/main/resources/medicine_master.csv backend/src/main/resources/
cd backend && mvn spring-boot:run

# 4. Web
cd web && npm install && npm run dev

# 5. Mobile
cd mobile && npm install && npx expo start
```

## Deploy
```bash
cd terraform
terraform init
terraform apply -var db_password=... -var jwt_secret=...
# Push backend image:
$(aws ecr get-login-password | docker login --username AWS --password-stdin $(terraform output -raw ecr_repo_url))
docker build -t $(terraform output -raw ecr_repo_url):latest backend/
docker push $(terraform output -raw ecr_repo_url):latest
aws ecs update-service --cluster $(terraform output -raw ecs_cluster) --service $(terraform output -raw ecs_service) --force-new-deployment
```

## Latest Spring AI / Java-AI features demonstrated
- **Spring AI 1.0 ChatClient fluent API** with default & per-call advisors
- **Agentic tool calling** via `@Tool` + `@ToolParam` (replaces old `FunctionCallback`)
- **RAG with `QuestionAnswerAdvisor`** over `PgVectorStore` (HNSW + cosine)
- **Chat memory advisor** (`MessageChatMemoryAdvisor`) for multi-turn sessions
- **Reactive SSE streaming** endpoint (`/api/chat/stream`) using WebFlux
- **Ollama auto-configuration** — same code swaps to Bedrock/OpenAI by changing a starter
- **Flyway + pgvector HNSW index** managed from the Boot app
