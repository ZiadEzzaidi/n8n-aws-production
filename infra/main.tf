terraform {
  required_version = ">= 1.6"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "aws" {
  region = var.region
  default_tags {
    tags = {
      Project     = "n8n-production"
      Environment = var.environment
    }
  }
}

locals {
  name          = "n8n-${var.environment}"
  secret_prefix = "/n8n/${var.environment}"

  # One configuration recipe, used at first boot and for in-place updates (scripts/deploy-server.ps1).
  configure_script = templatefile("${path.module}/configure.sh.tftpl", {
    region        = var.region
    secret_prefix = local.secret_prefix
    n8n_version   = var.n8n_version
    timezone      = var.timezone
    domain        = var.domain
    compose_b64   = filebase64("${path.module}/../compose.yaml")
    caddyfile_b64 = filebase64("${path.module}/../Caddyfile")
  })
}

data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }
}

data "aws_vpc" "default" {
  default = true
}

# --- Secrets: generated once, stored encrypted in Parameter Store, never on disk in the repo ---

resource "random_password" "postgres" {
  length  = 32
  special = false
}

resource "random_password" "encryption_key" {
  length  = 48
  special = false
}

resource "aws_ssm_parameter" "postgres_password" {
  name  = "${local.secret_prefix}/postgres_password"
  type  = "SecureString"
  value = random_password.postgres.result
}

resource "aws_ssm_parameter" "encryption_key" {
  name  = "${local.secret_prefix}/encryption_key"
  type  = "SecureString"
  value = random_password.encryption_key.result
}

# --- Server role: Systems Manager access + read access to its own two secrets only ---

data "aws_iam_policy_document" "assume_ec2" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "server" {
  name               = "${local.name}-server"
  assume_role_policy = data.aws_iam_policy_document.assume_ec2.json
}

resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.server.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

data "aws_iam_policy_document" "read_secrets" {
  statement {
    actions = ["ssm:GetParameter"]
    resources = [
      aws_ssm_parameter.postgres_password.arn,
      aws_ssm_parameter.encryption_key.arn,
    ]
  }
}

resource "aws_iam_role_policy" "read_secrets" {
  name   = "read-n8n-secrets"
  role   = aws_iam_role.server.id
  policy = data.aws_iam_policy_document.read_secrets.json
}

resource "aws_iam_instance_profile" "server" {
  name = "${local.name}-server"
  role = aws_iam_role.server.name
}

# --- Firewall: web traffic only (HTTP for certificate issuance and redirect, HTTPS). No SSH, n8n port closed ---

resource "aws_security_group" "n8n" {
  name = "${local.name}-web"
  # Description is immutable in AWS: editing it would replace the group, so the original text stays.
  description = "n8n editor from the owner IP only"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "HTTP for the Lets Encrypt challenge and redirect to HTTPS"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# --- Server: installs Docker, reads secrets, runs the same compose.yaml as local ---

resource "aws_instance" "server" {
  ami                         = data.aws_ami.al2023.id
  instance_type               = var.instance_type
  iam_instance_profile        = aws_iam_instance_profile.server.name
  vpc_security_group_ids      = [aws_security_group.n8n.id]
  user_data_replace_on_change = false

  user_data = templatefile("${path.module}/user-data.sh.tftpl", {
    configure_b64 = base64encode(local.configure_script)
  })

  metadata_options {
    http_tokens   = "required"
    http_endpoint = "enabled"
  }

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
    encrypted   = true
  }

  tags = {
    Name = "${local.name}-server"
  }

  # The server holds the data: never replace it because the boot script or the
  # latest AMI changed. n8n upgrades are applied in place (see scripts).
  lifecycle {
    ignore_changes = [ami, user_data]
  }

  depends_on = [aws_iam_role_policy.read_secrets]
}
