# GitHub Actions — Secrets Reference

Every secret goes into: **GitHub → Your Repo → Settings → Secrets and variables → Actions → New repository secret**

---

## Complete secrets list

| Secret name | Where used | How to get the value |
|---|---|---|
| `AWS_DEPLOY_ROLE_ARN` | All workflows | See "Create the OIDC IAM Role" below |
| `ECR_REGISTRY` | backend.yml | `terraform output -raw ecr_registry` (after first `terraform apply`) |
| `WEB_BUCKET` | web.yml | `terraform output -raw web_bucket` |
| `CF_DIST_ID` | web.yml | `terraform output -raw cloudfront_id` |
| `VITE_API_BASE` | web.yml (optional) | `http://<EC2-public-IP>:8080/api` — get IP from AWS Console → EC2 |
| `TF_STATE_BUCKET` | terraform.yml | Create manually — see step below |
| `TF_VAR_DB_PASSWORD` | terraform.yml | `openssl rand -base64 16` — **save this somewhere safe** |
| `TF_VAR_JWT_SECRET` | terraform.yml | `openssl rand -base64 32` — **save this somewhere safe** |
| `EXPO_TOKEN` | mobile.yml | https://expo.dev/accounts/[user]/settings/access-tokens |
| `CONFLUENCE_URL` | docs.yml | Your Confluence URL, e.g. `https://your-org.atlassian.net/wiki` |
| `CONFLUENCE_EMAIL` | docs.yml | Your Atlassian account email |
| `CONFLUENCE_API_TOKEN` | docs.yml | https://id.atlassian.com/manage-profile/security/api-tokens |
| `CONFLUENCE_SPACE_KEY` | docs.yml | Space key from Confluence → Space Settings (e.g. `HOMEO`) |
| `CONFLUENCE_PARENT_PAGE` | docs.yml (optional) | Parent page title, default: `Homeo AI` |

---

## Step 1 — Create the TF_STATE_BUCKET (one-time, manual)

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
BUCKET="homeo-ai-tfstate-${ACCOUNT_ID}"

aws s3api create-bucket \
  --bucket "$BUCKET" \
  --region ap-south-1 \
  --create-bucket-configuration LocationConstraint=ap-south-1

aws s3api put-bucket-versioning \
  --bucket "$BUCKET" \
  --versioning-configuration Status=Enabled

aws s3api put-public-access-block \
  --bucket "$BUCKET" \
  --public-access-block-configuration \
  "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"

echo "TF_STATE_BUCKET = $BUCKET"
# → Add this value as a GitHub secret: TF_STATE_BUCKET
```

---

## Step 2 — Create the OIDC IAM Role (one-time, manual)

This lets GitHub Actions assume an AWS role using short-lived tokens (no long-lived access keys stored in secrets).

### 2a. Create the OIDC Identity Provider

```bash
# Only needed once per AWS account
aws iam create-open-id-connect-provider \
  --url https://token.actions.githubusercontent.com \
  --client-id-list sts.amazonaws.com \
  --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1
```

### 2b. Create the IAM Role

Replace `YOUR_ORG` and `YOUR_REPO` with your GitHub org and repo name.

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ORG="sumitpalsingh007"            # e.g. sumitpalsingh007
REPO="homeopathy-recommender"   # correct repo name

cat > trust-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {
      "Federated": "arn:aws:iam::${ACCOUNT_ID}:oidc-provider/token.actions.githubusercontent.com"
    },
    "Action": "sts:AssumeRoleWithWebIdentity",
    "Condition": {
      "StringEquals": {
        "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
      },
      "StringLike": {
        "token.actions.githubusercontent.com:sub": "repo:sumitpalsingh007/homeopathy-recommender:*"
      }
    }
  }]
}
EOF

ROLE_ARN=$(aws iam create-role \
  --role-name homeo-ai-deploy \
  --assume-role-policy-document file://trust-policy.json \
  --query "Role.Arn" --output text)

echo "AWS_DEPLOY_ROLE_ARN = $ROLE_ARN"
# → Add this value as a GitHub secret: AWS_DEPLOY_ROLE_ARN
```

### 2c. Attach permissions to the role

```bash
# Terraform needs broad permissions to create all infrastructure
aws iam attach-role-policy \
  --role-name homeo-ai-deploy \
  --policy-arn arn:aws:iam::aws:policy/AdministratorAccess

# OR use minimal policies (recommended for production):
# aws iam attach-role-policy --role-name homeo-ai-deploy --policy-arn arn:aws:iam::aws:policy/AmazonEC2FullAccess
# aws iam attach-role-policy --role-name homeo-ai-deploy --policy-arn arn:aws:iam::aws:policy/AmazonRDSFullAccess
# aws iam attach-role-policy --role-name homeo-ai-deploy --policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess
# aws iam attach-role-policy --role-name homeo-ai-deploy --policy-arn arn:aws:iam::aws:policy/CloudFrontFullAccess
# aws iam attach-role-policy --role-name homeo-ai-deploy --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPowerUser
# aws iam attach-role-policy --role-name homeo-ai-deploy --policy-arn arn:aws:iam::aws:policy/AmazonSSMFullAccess
# aws iam attach-role-policy --role-name homeo-ai-deploy --policy-arn arn:aws:iam::aws:policy/IAMFullAccess
# aws iam attach-role-policy --role-name homeo-ai-deploy --policy-arn arn:aws:iam::aws:policy/AmazonVPCFullAccess
# aws iam attach-role-policy --role-name homeo-ai-deploy --policy-arn arn:aws:iam::aws:policy/AmazonElasticFileSystemFullAccess

rm trust-policy.json
```

---

## Step 3 — First terraform apply (manual, before CI works)

Run this once locally to create all infrastructure. After this, CI/CD takes over.

```bash
cd terraform

terraform init \
  -backend-config="bucket=homeo-ai-tfstate-${ACCOUNT_ID}" \
  -backend-config="key=mvp/terraform.tfstate" \
  -backend-config="region=ap-south-1"

terraform plan \
  -var="db_password=${TF_VAR_DB_PASSWORD}" \
  -var="jwt_secret=${TF_VAR_JWT_SECRET}" \
  -out=tfplan

terraform apply tfplan

# After apply, get the values for your remaining GitHub secrets:
echo "ECR_REGISTRY = $(terraform output -raw ecr_registry)"
echo "WEB_BUCKET   = $(terraform output -raw web_bucket)"
echo "CF_DIST_ID   = $(terraform output -raw cloudfront_id)"
```

Then add `ECR_REGISTRY`, `WEB_BUCKET`, `CF_DIST_ID` to GitHub Secrets.

---

## Step 4 — Activate Cost Explorer tag

AWS Cost Explorer doesn't show custom tags until you activate them:

```bash
aws ce create-cost-category-definition ... # Not needed — just activate the tag:
```

1. Go to **AWS Console → Billing → Cost Explorer → Cost allocation tags**
2. Find `appName` in the list
3. Click **Activate**
4. Wait 24 hours for data to appear

After activation, in Cost Explorer:
- Group by: **Tag → appName**
- Filter by: **appName = homeopathy-recommender**

---

## Step 5 — Create Confluence API token

1. Log in to https://id.atlassian.com
2. Go to **Security → API tokens → Create API token**
3. Label: `GitHub Actions homeo-ai-docs`
4. Copy the token (you can't see it again)
5. Add as `CONFLUENCE_API_TOKEN` in GitHub Secrets

---

## Summary: secrets to add in order

```
# First (before anything works):
TF_STATE_BUCKET       homeo-ai-tfstate-123456789012
AWS_DEPLOY_ROLE_ARN   arn:aws:iam::123456789012:role/homeo-ai-deploy
TF_VAR_DB_PASSWORD    (openssl rand -base64 16)
TF_VAR_JWT_SECRET     (openssl rand -base64 32)

# After first terraform apply:
ECR_REGISTRY          123456789012
WEB_BUCKET            homeo-ai-web-123456789012
CF_DIST_ID            EXXXXXXXXXXXXXXX
VITE_API_BASE         http://<EC2-IP>:8080/api

# For Confluence docs:
CONFLUENCE_URL          https://your-org.atlassian.net/wiki
CONFLUENCE_EMAIL        you@example.com
CONFLUENCE_API_TOKEN    (from id.atlassian.com)
CONFLUENCE_SPACE_KEY    HOMEO

# For mobile (optional):
EXPO_TOKEN              (from expo.dev)
```

---

## Security note

None of the workflows use `AWS_ACCESS_KEY_ID` or `AWS_SECRET_ACCESS_KEY`. All AWS authentication uses **OIDC** (OpenID Connect), which issues short-lived tokens per-run. This means:
- No long-lived AWS credentials stored in GitHub
- Tokens automatically expire after each workflow run
- If someone forks your repo, they cannot assume your AWS role (the trust policy is scoped to your exact repo)
