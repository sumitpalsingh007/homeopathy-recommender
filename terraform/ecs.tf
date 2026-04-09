#############################
# ECS Fargate cluster running:
#  - backend container  (Spring Boot)
#  - ollama sidecar     (self-hosted LLM, same task for zero network cost)
# Uses a single task (1 vCPU / 3 GB) to keep costs minimal (~$15-20/mo).
# No ALB: a single public task + Route53 A-alias to a CloudFront/Lambda
# isn't free either — for MVP we expose the task's public IP through a
# cheap NLB only if DNS/TLS is needed; here we use ECS Service Connect + Fargate public IP.
#############################
resource "aws_ecr_repository" "backend" {
  name                 = "${var.project}-backend"
  image_tag_mutability = "MUTABLE"
  force_delete         = true
}

resource "aws_ecs_cluster" "main" {
  name = var.project
  setting {
    name  = "containerInsights"
    value = "disabled" # cost saver
  }
}

resource "aws_cloudwatch_log_group" "backend" {
  name              = "/ecs/${var.project}-backend"
  retention_in_days = 7
}

data "aws_iam_policy_document" "assume_ecs_task" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "task_exec" {
  name               = "${var.project}-task-exec"
  assume_role_policy = data.aws_iam_policy_document.assume_ecs_task.json
}
resource "aws_iam_role_policy_attachment" "task_exec" {
  role       = aws_iam_role.task_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role" "task" {
  name               = "${var.project}-task"
  assume_role_policy = data.aws_iam_policy_document.assume_ecs_task.json
}

resource "aws_ecs_task_definition" "backend" {
  family                   = "${var.project}-backend"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "1024"
  memory                   = "3072"
  execution_role_arn       = aws_iam_role.task_exec.arn
  task_role_arn            = aws_iam_role.task.arn

  container_definitions = jsonencode([
    {
      name      = "ollama"
      image     = "ollama/ollama:latest"
      essential = true
      portMappings = [{ containerPort = 11434, protocol = "tcp" }]
      environment = [
        { name = "OLLAMA_KEEP_ALIVE", value = "30m" }
      ]
      # Pull model on first start; Ollama caches inside task ephemeral storage.
      command = ["sh", "-c", "ollama serve & sleep 5 && ollama pull ${var.ollama_model} && ollama pull nomic-embed-text && wait"]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.backend.name
          "awslogs-region"        = var.region
          "awslogs-stream-prefix" = "ollama"
        }
      }
    },
    {
      name      = "backend"
      image     = "${aws_ecr_repository.backend.repository_url}:latest"
      essential = true
      portMappings = [{ containerPort = 8080, protocol = "tcp" }]
      dependsOn = [{ containerName = "ollama", condition = "START" }]
      environment = [
        { name = "DB_URL",        value = "jdbc:postgresql://${aws_db_instance.postgres.address}:5432/homeo" },
        { name = "DB_USER",       value = "homeo" },
        { name = "DB_PASSWORD",   value = var.db_password },
        { name = "JWT_SECRET",    value = var.jwt_secret },
        { name = "OLLAMA_URL",    value = "http://localhost:11434" },
        { name = "OLLAMA_CHAT_MODEL",  value = var.ollama_model },
        { name = "OLLAMA_EMBED_MODEL", value = "nomic-embed-text" },
        { name = "CORS_ORIGINS",  value = "*" }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.backend.name
          "awslogs-region"        = var.region
          "awslogs-stream-prefix" = "backend"
        }
      }
    }
  ])

  ephemeral_storage { size_in_gib = 30 }   # holds Ollama model weights
}

resource "aws_ecs_service" "backend" {
  name            = "${var.project}-backend"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.backend.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = aws_subnet.public[*].id
    security_groups  = [aws_security_group.app.id]
    assign_public_ip = true
  }
  deployment_minimum_healthy_percent = 0
  deployment_maximum_percent         = 100
}
