output "rds_password" {
  value     = local.rds_password
  sensitive = true
}
output "rds_endpoint"           { value = aws_db_instance.postgres.address }
output "rds_port"               { value = "5432" }
output "rds_database"           { value = "homeo" }
output "web_bucket"             { value = aws_s3_bucket.web.bucket }
output "cloudfront_domain"      { value = aws_cloudfront_distribution.web.domain_name }
output "cloudfront_id"          { value = aws_cloudfront_distribution.web.id }
output "asg_name"               { value = aws_autoscaling_group.backend.name }
output "backend_security_group" { value = aws_security_group.app.id }
output "backend_log_group"      { value = aws_cloudwatch_log_group.backend.name }

# ECR — copy these into GitHub Secrets after first terraform apply
# ecr_registry = the registry host only (no repo suffix) → set as ECR_REGISTRY secret
# Format: 123456789012.dkr.ecr.ap-south-1.amazonaws.com
output "ecr_registry" {
  value = "${data.aws_caller_identity.me.account_id}.dkr.ecr.${var.region}.amazonaws.com"
}
output "ecr_repo_url"    { value = aws_ecr_repository.backend.repository_url }

# EFS — informational
output "efs_dns"         { value = aws_efs_file_system.ollama_cache.dns_name }
output "efs_id"          { value = aws_efs_file_system.ollama_cache.id }
