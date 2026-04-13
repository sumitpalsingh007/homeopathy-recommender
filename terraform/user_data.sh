#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# EC2 user_data.sh — runs once on every instance boot.
#
# Cold start fix: we mount the EFS filesystem at /root/.ollama BEFORE starting
# Ollama. This means:
#   • First boot (EFS is empty):  Ollama downloads models once (~10 min)
#   • Every subsequent boot:      Models already in EFS → Ollama starts in ~30 sec
#   • After Spot interruption:    ASG launches a replacement → mounts same EFS
#                                 → Ollama finds its models → starts in ~30 sec ✓
# ─────────────────────────────────────────────────────────────────────────────
set -e
exec > >(tee /var/log/user-data.log) 2>&1

echo "=== [$(date)] EC2 bootstrap starting ==="
echo "EFS DNS : ${efs_dns}"
echo "Region  : ${region}"

# ─── 1. System packages ───────────────────────────────────────────────────────
yum update -y
yum install -y docker amazon-efs-utils amazon-cloudwatch-agent jq curl

# ─── 2. Start Docker ──────────────────────────────────────────────────────────
systemctl start docker
systemctl enable docker
usermod -aG docker ec2-user

# ─── 3. Mount EFS at /root/.ollama (Ollama model cache) ──────────────────────
# amazon-efs-utils uses TLS + stunnel and is already installed above.
mkdir -p /root/.ollama

# Try to mount; retry up to 10× in case EFS mount targets aren't ready yet
for i in $(seq 1 10); do
  if mount -t efs -o tls "${efs_dns}:/" /root/.ollama; then
    echo "✓ EFS mounted at /root/.ollama"
    break
  fi
  echo "Attempt $i/10: EFS not ready yet, retrying in 15 s..."
  sleep 15
done

# Verify mount succeeded; if not, fall back to local storage (models will be
# re-downloaded, but the app still starts — just slower the next time too).
if ! mountpoint -q /root/.ollama; then
  echo "⚠ EFS mount failed after retries — using local storage (models will re-download)"
else
  # Add to /etc/fstab so the mount survives reboots
  echo "${efs_dns}:/ /root/.ollama efs _netdev,tls 0 0" >> /etc/fstab
fi

# ─── 4. Create project directory ─────────────────────────────────────────────
mkdir -p /opt/homeo-ai
cd /opt/homeo-ai

# ─── 5. Write docker-compose.yml ─────────────────────────────────────────────
cat > docker-compose.yml << 'COMPOSE_EOF'
version: '3.8'

services:
  ollama:
    image: ollama/ollama:latest
    container_name: ollama
    ports:
      - "11434:11434"
    environment:
      OLLAMA_KEEP_ALIVE: "60m"
    volumes:
      # Mount EFS (already mounted at /root/.ollama) into the container.
      # Model weights persist across instance replacements via EFS.
      - /root/.ollama:/root/.ollama
    restart: unless-stopped
    networks:
      - app-net
    healthcheck:
      test: ["CMD", "curl", "-sf", "http://localhost:11434/api/tags"]
      interval: 10s
      timeout: 5s
      retries: 6

  backend:
    image: ${ecr_repo_url}:latest
    container_name: backend
    ports:
      - "8080:8080"
    environment:
      DB_URL:               "jdbc:postgresql://${db_host}:5432/homeo"
      DB_USER:              "${db_user}"
      DB_PASSWORD:          "${db_password}"
      JWT_SECRET:           "${jwt_secret}"
      OLLAMA_URL:           "http://ollama:11434"
      OLLAMA_CHAT_MODEL:    "${ollama_model}"
      OLLAMA_EMBED_MODEL:   "nomic-embed-text"
      CORS_ORIGINS:         "*"
      JAVA_OPTS:            "-Xms256m -Xmx512m"
    depends_on:
      ollama:
        condition: service_healthy
    restart: unless-stopped
    networks:
      - app-net
    healthcheck:
      test: ["CMD", "curl", "-sf", "http://localhost:8080/actuator/health"]
      interval: 15s
      timeout: 5s
      retries: 8

volumes: {}

networks:
  app-net:
    driver: bridge
COMPOSE_EOF

# ─── 6. Substitute real values into docker-compose.yml ───────────────────────
# Extract DB hostname from JDBC URL: jdbc:postgresql://hostname:5432/...
DB_HOST=$(echo "${db_url}" | sed 's|jdbc:postgresql://||' | cut -d: -f1)

sed -i \
  -e "s|\${ecr_repo_url}|${ecr_repo_url}|g" \
  -e "s|\${db_host}|$DB_HOST|g" \
  -e "s|\${db_user}|${db_user}|g" \
  -e "s|\${db_password}|${db_password}|g" \
  -e "s|\${jwt_secret}|${jwt_secret}|g" \
  -e "s|\${ollama_model}|${ollama_model}|g" \
  docker-compose.yml

# ─── 7. Authenticate Docker to ECR ───────────────────────────────────────────
aws ecr get-login-password --region "${region}" \
  | docker login \
      --username AWS \
      --password-stdin "${ecr_registry}.dkr.ecr.${region}.amazonaws.com"

# ─── 8. Pull images ───────────────────────────────────────────────────────────
docker-compose pull

# ─── 9. Start Ollama first so it can serve models while backend loads ─────────
docker-compose up -d ollama

echo "=== Waiting for Ollama to be ready ==="
# Ollama starts fast now that EFS already has model weights.
for i in $(seq 1 60); do
  if curl -sf http://localhost:11434/api/tags > /dev/null 2>&1; then
    echo "✓ Ollama is ready"
    break
  fi
  echo "  attempt $i/60 — Ollama not ready yet..."
  sleep 5
done

# Pull models only if they are NOT already in EFS (idempotent)
MODELS_PRESENT=$(curl -sf http://localhost:11434/api/tags | jq '.models | length' 2>/dev/null || echo "0")
if [ "$MODELS_PRESENT" -eq "0" ]; then
  echo "=== Models not found in EFS — downloading (first boot only) ==="
  docker exec ollama ollama pull "${ollama_model}"
  docker exec ollama ollama pull nomic-embed-text
  echo "✓ Models downloaded and cached in EFS — future boots will be fast"
else
  echo "✓ Models already in EFS ($MODELS_PRESENT model(s)) — skipping download"
fi

# ─── 10. Start backend ────────────────────────────────────────────────────────
docker-compose up -d backend

echo "=== Waiting for Spring Boot to be healthy ==="
for i in $(seq 1 60); do
  if curl -sf http://localhost:8080/actuator/health > /dev/null 2>&1; then
    echo "✓ Backend is healthy"
    break
  fi
  echo "  attempt $i/60 — backend not ready yet..."
  sleep 5
done

echo "=== [$(date)] Bootstrap complete ==="
echo ""
echo "  Ollama: http://localhost:11434/api/tags"
echo "  Backend: http://localhost:8080/actuator/health"
