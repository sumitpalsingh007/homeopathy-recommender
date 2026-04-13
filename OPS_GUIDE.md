# Operations & Troubleshooting Guide

## Dashboard commands (bookmarks for Slack/terminal)

Keep these handy during launches:

```bash
# Check if instance is running
alias homeo_status='aws ec2 describe-instances --filters "Name=tag:Name,Values=homeo-ai-backend" --region ap-south-1 --query "Reservations[0].Instances[0].[InstanceId,State.Name,PublicIpAddress]" --output table'

# Tail logs in real-time
alias homeo_logs='aws logs tail /ec2/homeo-ai-backend --follow --region ap-south-1'

# Check ASG health
alias homeo_health='aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names homeo-ai-asg --region ap-south-1 --query "AutoScalingGroups[0].Instances[*].[InstanceId,HealthStatus,LifecycleState]" --output table'

# Get backend IP
alias homeo_ip='aws ec2 describe-instances --filters "Name=tag:Name,Values=homeo-ai-backend" --region ap-south-1 --query "Reservations[0].Instances[0].PublicIpAddress" --output text'

# Get outputs
alias homeo_outputs='terraform -chdir=terraform output -json'

# Get CloudFront domain
alias homeo_domain='terraform -chdir=terraform output -raw cloudfront_domain'
```

---

## Pre-demo checklist (10 minutes before demo)

```bash
#!/bin/bash
# pre_demo_check.sh

set -e
REGION="ap-south-1"

echo "=== Pre-Demo Checklist ==="

# 1. Instance status
echo "✓ Checking EC2 instance..."
aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=homeo-ai-backend" \
  --region $REGION \
  --query 'Reservations[0].Instances[0].[State.Name,PublicIpAddress]' \
  --output text

# 2. Health endpoint
echo "✓ Checking backend health..."
INSTANCE_IP=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=homeo-ai-backend" \
  --region $REGION \
  --query 'Reservations[0].Instances[0].PublicIpAddress' \
  --output text)

if curl -f http://$INSTANCE_IP:8080/actuator/health >/dev/null 2>&1; then
  echo "✓ Backend is healthy"
else
  echo "✗ Backend is NOT responding. Check logs."
  aws logs tail /ec2/homeo-ai-backend --follow --region $REGION
  exit 1
fi

# 3. Database connectivity
echo "✓ Checking database..."
DB_ENDPOINT=$(terraform -chdir=terraform output -raw rds_endpoint)
if psql -h $DB_ENDPOINT -U homeo -d homeo -c "SELECT 1" 2>/dev/null; then
  echo "✓ Database is accessible"
else
  echo "⚠ Database not responding (OK if just deployed)"
fi

# 4. Frontend
echo "✓ Checking frontend..."
CLOUDFRONT=$(terraform -chdir=terraform output -raw cloudfront_domain)
if curl -s "https://$CLOUDFRONT/index.html" | grep -q "<title>"; then
  echo "✓ Frontend is deployed"
else
  echo "✗ Frontend is not responding"
fi

echo ""
echo "=== Demo is ready! ==="
echo "Frontend: https://$CLOUDFRONT"
echo "Backend: http://$INSTANCE_IP:8080"
echo ""
```

---

## Monitoring Spot interruptions

AWS Spot instances get 2-minute warnings before termination. The ASG auto-replaces them.

```bash
# Monitor in real-time
watch -n 5 'aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names homeo-ai-asg \
  --region ap-south-1 \
  --query "AutoScalingGroups[0].Instances[*].[InstanceId,HealthStatus,LifecycleState]" \
  --output table'

# View recent scaling activities
aws autoscaling describe-scaling-activities \
  --auto-scaling-group-name homeo-ai-asg \
  --region ap-south-1 \
  --max-records 20 \
  --query 'Activities[*].[StartTime,Description,Cause]' \
  --output table

# Set up SNS alert (optional, email when instance is interrupted)
aws autoscaling put-notification-configuration \
  --auto-scaling-group-name homeo-ai-asg \
  --topic-arn arn:aws:sns:ap-south-1:ACCOUNT:homeo-alerts \
  --notification-types "autoscaling:EC2_INSTANCE_TERMINATE" \
  --region ap-south-1
```

---

## Debugging: Backend is slow

**Symptoms:** First request takes 5–10 seconds, subsequent requests are 2–3 seconds.

**Diagnosis:**

1. **Ollama model is loading into memory.** This is expected. Subsequent requests reuse the loaded model.

   ```bash
   # Check Ollama is loaded
   curl http://$(homeo_ip):11434/api/tags

   # Expected: { "models": [{ "name": "llama3.1:8b-instruct-q4_0" }] }
   ```

2. **Check recent logs for errors:**

   ```bash
   aws logs tail /ec2/homeo-ai-backend --follow --region ap-south-1 | grep -i error
   ```

3. **Check Spring Boot startup time:**

   ```bash
   aws logs get-log-events \
     --log-group-name /ec2/homeo-ai-backend \
     --log-stream-name backend \
     --region ap-south-1 \
     --query 'events[*].message' \
     --output text | grep "Started HomeoAiApplication"
   ```

---

## Debugging: "Connection refused" from frontend

**Symptoms:** Frontend loads, but clicking "Send" shows error.

**Diagnosis:**

1. **Backend endpoint is wrong.** Check the frontend is calling the correct backend URL.

   ```bash
   # In browser DevTools (F12 → Network), what URL is being called?
   # Should be: https://<cloudfront-domain>/api/chat
   ```

2. **CORS is blocking the request.** Backend should allow CloudFront domain.

   ```bash
   # Check CORS env var in user_data.sh
   # Should include: CORS_ORIGINS: "*"

   # Or set explicitly to CloudFront domain:
   # CORS_ORIGINS: "https://$(terraform output -raw cloudfront_domain)"
   ```

3. **Backend security group doesn't allow inbound traffic.**

   ```bash
   # Check security group rules
   aws ec2 describe-security-groups \
     --group-ids $(terraform output -raw backend_security_group) \
     --region ap-south-1 \
     --query 'SecurityGroups[0].IpPermissions' \
     --output table

   # Should show: Port 8080, CIDR 0.0.0.0/0
   ```

---

## Debugging: Database won't connect

**Symptoms:** Backend logs show `SQLException: could not connect to server`.

**Diagnosis:**

1. **RDS instance is not ready yet.** Takes 5–10 minutes on first deploy.

   ```bash
   aws rds describe-db-instances \
     --db-instance-identifier homeo-ai-db \
     --region ap-south-1 \
     --query 'DBInstances[0].[DBInstanceStatus,Endpoint.Address]' \
     --output text

   # Wait for Status: "available"
   ```

2. **RDS security group is too restrictive.** Should allow traffic from EC2 app SG.

   ```bash
   aws ec2 describe-security-groups \
     --filters "Name=group-name,Values=homeo-ai-db" \
     --region ap-south-1 \
     --query 'SecurityGroups[0].IpPermissions' \
     --output table

   # Should show: Port 5432, SourceSecurityGroupId = backend SG
   ```

3. **Database was not initialized.** RDS doesn't auto-run Flyway migrations on first boot.

   ```bash
   # SSH into backend instance and manually init DB
   INSTANCE_IP=$(homeo_ip)
   aws ssm start-session --target $(aws ec2 describe-instances \
     --filters "Name=private-ip-address,Values=$INSTANCE_IP" \
     --region ap-south-1 \
     --query 'Reservations[0].Instances[0].InstanceId' \
     --output text) \
     --region ap-south-1

   # Inside the instance:
   docker-compose exec backend curl http://localhost:8080/actuator/health
   docker-compose logs backend | grep -i flyway
   ```

---

## Manual instance recovery

If the ASG instance is stuck or you need to restart:

```bash
# Get current instance ID
INSTANCE_ID=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=homeo-ai-backend" \
  --region ap-south-1 \
  --query 'Reservations[0].Instances[0].InstanceId' \
  --output text)

# Terminate (ASG will launch a replacement)
aws ec2 terminate-instances --instance-ids $INSTANCE_ID --region ap-south-1

# Watch replacement:
watch -n 5 'aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names homeo-ai-asg \
  --region ap-south-1 \
  --query "AutoScalingGroups[0].Instances[*].[InstanceId,LifecycleState]" \
  --output table'
```

---

## Cost analysis

**Check your actual spend so far:**

```bash
aws ce get-cost-and-usage \
  --time-period Start=2026-04-01,End=2026-04-30 \
  --granularity DAILY \
  --metrics BlendedCost \
  --group-by Type=DIMENSION,Key=SERVICE \
  --region ap-south-1 \
  --query 'ResultsByTime[*].[TimePeriod.Start,Groups[?Keys[0]==`Amazon Elastic Compute Cloud - Compute`].Metrics.BlendedCost[0]]' \
  --output table
```

**Expected breakdown:**
- EC2 Spot: $0–1 (within free tier 750 hrs)
- RDS: $2–4 (slightly over free tier after 750 hrs)
- Other: <$1

---

## Performance tuning

### Ollama inference is slow (first request 5+ sec)

**Options:**
1. **Increase model precision** (currently q4_0 quantized): Download larger model, trades memory for speed
2. **Use a smaller model**: Replace `llama3.1:8b` with `llama2:7b` (faster, less capable)
3. **Increase instance size**: Switch to t3.small ($2–3/mo extra), dedicates more CPU to Ollama

**Change model in terraform/variables.tf:**
```hcl
variable "ollama_model" {
  default = "llama2:7b-instruct-q4_0"  # Faster
  # or
  default = "mistral:7b-instruct-q4_0"  # Also good
}

terraform apply -var="db_password=$DB_PASSWORD" -var="jwt_secret=$JWT_SECRET"
```

### Spring Boot startup is slow

**Check if using too much memory:**
```bash
# Inside EC2 instance
free -h
docker stats --no-stream backend
```

**If OOM errors appear, increase instance size or reduce `-Xmx` in user_data.sh**.

---

## Backup & recovery

### Backup RDS database

```bash
# Create manual snapshot
aws rds create-db-snapshot \
  --db-instance-identifier homeo-ai-db \
  --db-snapshot-identifier homeo-backup-$(date +%Y%m%d) \
  --region ap-south-1

# List snapshots
aws rds describe-db-snapshots --region ap-south-1 --query 'DBSnapshots[*].[DBSnapshotIdentifier,CreateTime]'
```

### Restore from snapshot

```bash
aws rds restore-db-instance-from-db-snapshot \
  --db-instance-identifier homeo-ai-db-restored \
  --db-snapshot-identifier homeo-backup-20260410 \
  --region ap-south-1
```

---

## Cleanup after April 30

When free tier ends or you want to stop incurring costs:

```bash
# Destroy all infrastructure (keeps S3 Terraform state)
terraform -chdir=terraform destroy \
  -var="db_password=$DB_PASSWORD" \
  -var="jwt_secret=$JWT_SECRET"

# This removes:
# - EC2 instance + ASG
# - RDS database
# - VPC + subnets + security groups
# - CloudFront + S3 web bucket
# - IAM roles

# Keep S3 state bucket for future `terraform apply`
```

---

## Emergency contacts / escalation

If something goes critically wrong:

1. **Check CloudWatch logs** — most issues are visible here
2. **Check Terraform state** — `terraform show` shows what's deployed
3. **Check AWS console** — EC2 → Instances, RDS → Databases
4. **Nuke and redeploy** — if state is corrupted, `terraform destroy` and `terraform apply` again

Good luck! 🚀
