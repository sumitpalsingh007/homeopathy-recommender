terraform {
  required_version = ">= 1.9.0"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.60" }
  }
  backend "s3" {
    bucket = "homeo-ai-tfstate"
    key    = "mvp/terraform.tfstate"
    region = "ap-south-1"
  }
}

provider "aws" {
  region = var.region
}
