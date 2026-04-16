terraform {
  required_version = ">= 1.9.0"
  required_providers {
    aws    = { source = "hashicorp/aws",        version = "~> 5.60" }
    random = { source = "hashicorp/random",     version = "~> 3.6"  }
  }
  # Bucket name is passed at init time via -backend-config in CI.
  # For manual deploys: terraform init -backend-config="bucket=homeo-ai-tfstate-ACCOUNT_ID"
  backend "s3" {
    key    = "mvp/terraform.tfstate"
    region = "ap-south-1"
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# default_tags: applied to EVERY AWS resource created by this provider.
# This powers the Cost Explorer filter:
#   AWS Console → Billing → Cost Explorer → Group by Tag → appName
# ─────────────────────────────────────────────────────────────────────────────
provider "aws" {
  region = var.region

  default_tags {
    tags = {
      appName     = "homeopathy-recommender"   # ← billing tag
      Project     = var.project
      Environment = "mvp"
      ManagedBy   = "terraform"
      Repo        = "homeopathy-recommender"
    }
  }
}
