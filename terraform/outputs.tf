output "ecr_repo_url"        { value = aws_ecr_repository.backend.repository_url }
output "rds_endpoint"        { value = aws_db_instance.postgres.address }
output "web_bucket"          { value = aws_s3_bucket.web.bucket }
output "cloudfront_domain"   { value = aws_cloudfront_distribution.web.domain_name }
output "cloudfront_id"       { value = aws_cloudfront_distribution.web.id }
output "ecs_cluster"         { value = aws_ecs_cluster.main.name }
output "ecs_service"         { value = aws_ecs_service.backend.name }
