#############################
# ECR repository for the backend Docker image.
# GitHub Actions pushes here; EC2 user_data pulls from here on startup.
#############################

resource "aws_ecr_repository" "backend" {
  name                 = "${var.project}-backend"
  image_tag_mutability = "MUTABLE"
  force_delete         = true   # allows terraform destroy without manual image deletion

  image_scanning_configuration {
    scan_on_push = true   # free basic vulnerability scanning
  }

  tags = {
    Name = "${var.project}-backend-ecr"
  }
}

# Keep only the last 10 images to avoid runaway storage costs
resource "aws_ecr_lifecycle_policy" "backend" {
  repository = aws_ecr_repository.backend.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 10 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 10
      }
      action = { type = "expire" }
    }]
  })
}
