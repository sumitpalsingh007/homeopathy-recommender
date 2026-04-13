#############################
# RDS Postgres 16 with pgvector — smallest burstable, public subnets, private.
# db.t4g.micro ≈ $12/mo + 20GB gp3 ≈ $2.3/mo.
#############################

# Auto-generate a compliant RDS password.
# RDS rules: 8-41 chars, no /  "  @  or space.
# random_password with special=false produces only A-Z a-z 0-9 — always safe.
# If var.db_password is set (e.g. from GitHub secret), that is used instead.
resource "random_password" "rds" {
  length           = 24
  special          = false   # avoids / " @ and space that RDS rejects
}

locals {
  rds_password = var.db_password != "" ? var.db_password : random_password.rds.result
}

resource "aws_db_subnet_group" "main" {
  name       = "${var.project}-db"
  subnet_ids = aws_subnet.public[*].id
}

resource "aws_db_parameter_group" "pg16_vector" {
  name   = "${var.project}-pg16"
  family = "postgres16"
  parameter {
    name  = "shared_preload_libraries"
    value = "pg_stat_statements"
    apply_method = "pending-reboot"
  }
}

resource "aws_db_instance" "postgres" {
  identifier              = "${var.project}-db"
  engine                  = "postgres"
  engine_version          = "16"   # AWS picks the latest available patch in the region
  instance_class          = "db.t4g.micro"
  allocated_storage       = 20
  storage_type            = "gp3"
  db_name                 = "homeo"
  username                = "homeo"
  password                = local.rds_password
  db_subnet_group_name    = aws_db_subnet_group.main.name
  vpc_security_group_ids  = [aws_security_group.db.id]
  publicly_accessible     = false
  skip_final_snapshot     = true
  backup_retention_period = 1
  parameter_group_name    = aws_db_parameter_group.pg16_vector.name
  apply_immediately       = true
}
