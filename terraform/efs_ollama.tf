#############################
# EFS persistent volume for Ollama model weights.
#
# Problem solved: every time the Spot instance is interrupted/replaced, the
# ASG launches a fresh instance that has to re-download ~5 GB of model weights
# (llama3.1:8b-q4_0 + nomic-embed-text), which takes 8–15 minutes during which
# the app cannot serve requests.
#
# Fix: mount an EFS filesystem at /root/.ollama so the downloaded weights
# survive across instance replacements. First boot = 10 min (one-time download).
# All subsequent boots (including after Spot interruption) = ~30 sec.
#
# Cost: EFS Standard $0.30/GB-month, but model weights are ~5 GB =  ~$1.50/mo.
#       With EFS Intelligent Tiering they move to IA ($0.025/GB) after 90 days
#       of infrequent access → drops to ~$0.13/mo.
#       Either way well under the $5/mo budget.
#
# Security: EFS mount target only accepts NFS traffic from the app SG.
#############################

resource "aws_efs_file_system" "ollama_cache" {
  creation_token   = "${var.project}-ollama-cache"
  performance_mode = "generalPurpose"
  throughput_mode  = "bursting"

  # Move files to IA storage class after 90 days without access
  lifecycle_policy {
    transition_to_ia = "AFTER_90_DAYS"
  }

  # Bring back from IA on first access (so Ollama doesn't notice)
  lifecycle_policy {
    transition_to_primary_storage_class = "AFTER_1_ACCESS"
  }

  tags = {
    Name = "${var.project}-ollama-cache"
  }
}

# Security group for EFS — only accepts NFS (2049) from the app SG
resource "aws_security_group" "efs" {
  name        = "${var.project}-efs"
  description = "EFS access for Ollama model cache"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "NFS from EC2 instances"
    from_port       = 2049
    to_port         = 2049
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Create an EFS mount target in each public subnet so any AZ can reach it
resource "aws_efs_mount_target" "ollama_cache" {
  count           = 2
  file_system_id  = aws_efs_file_system.ollama_cache.id
  subnet_id       = aws_subnet.public[count.index].id
  security_groups = [aws_security_group.efs.id]
}
