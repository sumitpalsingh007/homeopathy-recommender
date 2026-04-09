#############################
# RDS Postgres 16 with pgvector — smallest burstable, public subnets, private.
# db.t4g.micro ≈ $12/mo + 20GB gp3 ≈ $2.3/mo.
#############################
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
  engine_version          = "16.4"
  instance_class          = "db.t4g.micro"
  allocated_storage       = 20
  storage_type            = "gp3"
  db_name                 = "homeo"
  username                = "homeo"
  password                = var.db_password
  db_subnet_group_name    = aws_db_subnet_group.main.name
  vpc_security_group_ids  = [aws_security_group.db.id]
  publicly_accessible     = false
  skip_final_snapshot     = true
  backup_retention_period = 1
  parameter_group_name    = aws_db_parameter_group.pg16_vector.name
  apply_immediately       = true
}
