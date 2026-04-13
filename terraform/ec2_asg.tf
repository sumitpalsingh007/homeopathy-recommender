#############################
# EC2 Spot instance + ASG with auto-recovery
# Runs backend + Ollama in Docker Compose (same image as before)
# Spot t3.micro: ~$2-3/mo (70% discount from on-demand $12/mo)
# ASG capacity-rebalance: auto-recovery on Spot termination
#############################

# IAM role for EC2 instance (CloudWatch + SSM access for troubleshooting)
data "aws_iam_policy_document" "assume_ec2" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ec2_role" {
  name               = "${var.project}-ec2-role"
  assume_role_policy = data.aws_iam_policy_document.assume_ec2.json
}

resource "aws_iam_role_policy_attachment" "ec2_cloudwatch" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_role_policy_attachment" "ec2_ssm" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# ECR pull: lets the EC2 instance pull Docker images from your private ECR repo
resource "aws_iam_role_policy_attachment" "ec2_ecr" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_instance_profile" "ec2" {
  name = "${var.project}-ec2-profile"
  role = aws_iam_role.ec2_role.name
}

resource "aws_cloudwatch_log_group" "backend" {
  name              = "/ec2/${var.project}-backend"
  retention_in_days = 7
}

# User data script: install Docker, mount EFS, pull images, start services
locals {
  user_data_script = base64encode(templatefile("${path.module}/user_data.sh", {
    db_url             = "jdbc:postgresql://${aws_db_instance.postgres.address}:5432/homeo"
    db_host            = aws_db_instance.postgres.address
    db_user            = "homeo"
    db_password        = local.rds_password
    jwt_secret         = var.jwt_secret
    ollama_model       = var.ollama_model
    region             = var.region
    log_group          = aws_cloudwatch_log_group.backend.name
    efs_dns            = aws_efs_file_system.ollama_cache.dns_name
    ecr_registry       = aws_ecr_repository.backend.registry_id
    ecr_repo_url       = aws_ecr_repository.backend.repository_url
  }))
}

# Launch template for Spot instances
resource "aws_launch_template" "backend" {
  name_prefix   = "${var.project}-"
  image_id      = data.aws_ami.amazon_linux_2.id
  instance_type = "t3.micro"

  iam_instance_profile {
    name = aws_iam_instance_profile.ec2.name
  }

  network_interfaces {
    associate_public_ip_address = true
    security_groups             = [aws_security_group.app.id]
    delete_on_termination       = true
  }

  # Spot instance configuration
  instance_market_options {
    market_type = "spot"
    spot_options {
      max_price                      = "0.01"   # t3.micro is ~$0.0076/hr; cap prevents surprise charges
      spot_instance_type             = "one-time"  # required for ASG; ASG handles relaunch itself
      instance_interruption_behavior = "terminate" # ASG replaces on termination via capacity_rebalance
    }
  }

  user_data     = local.user_data_script
  ebs_optimized = false

  monitoring {
    enabled = false  # detailed monitoring costs $0.0035/metric/month; enable later if needed
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name    = "${var.project}-backend"
      Project = var.project
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Auto-scaling group: maintains 1 instance, auto-replaces on Spot interruption
resource "aws_autoscaling_group" "backend" {
  name                = "${var.project}-asg"
  vpc_zone_identifier = aws_subnet.public[*].id
  min_size            = 1
  max_size            = 1
  desired_capacity    = 1

  # Capacity rebalancing: replaces Spot instances before termination
  capacity_rebalance  = true

  health_check_type         = "ELB"
  health_check_grace_period = 300

  launch_template {
    id      = aws_launch_template.backend.id
    version = "$Latest"
  }

  # Termination policies: remove new instance first (minimize disruption)
  termination_policies = [
    "OldestLaunchTemplate",
    "Default"
  ]

  # These tags are propagated to every EC2 instance launched by this ASG.
  # The appName tag is critical for AWS Cost Explorer "group by tag" billing.
  tag {
    key                 = "Name"
    value               = "${var.project}-backend"
    propagate_at_launch = true
  }
  tag {
    key                 = "appName"
    value               = "homeopathy-recommender"
    propagate_at_launch = true
  }
  tag {
    key                 = "Project"
    value               = var.project
    propagate_at_launch = true
  }
  tag {
    key                 = "ManagedBy"
    value               = "terraform"
    propagate_at_launch = true
  }

  lifecycle {
    create_before_destroy = true
  }
}

# CloudWatch alarm: alert if instance is unhealthy
resource "aws_cloudwatch_metric_alarm" "asg_health" {
  alarm_name          = "${var.project}-asg-unhealthy"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "2"
  metric_name         = "GroupInServiceInstances"
  namespace           = "AWS/AutoScaling"
  period              = "60"
  statistic           = "Average"
  threshold           = "1"
  treat_missing_data  = "breaching"

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.backend.name
  }

  alarm_actions = []  # Add SNS topic for email alerts if needed
}

# Data source: latest Amazon Linux 2 AMI
data "aws_ami" "amazon_linux_2" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}
