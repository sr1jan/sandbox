locals {
  tailnet_hostname = "dp-sandbox-${terraform.workspace}"
}

# ---- Ubuntu AMI lookup ----
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-arm64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# ---- VPC + subnet + IGW + routing ----
resource "aws_vpc" "sandbox" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = { Name = "sandbox-vpc-${terraform.workspace}" }
}

resource "aws_subnet" "sandbox_public" {
  vpc_id                  = aws_vpc.sandbox.id
  cidr_block              = var.subnet_cidr
  map_public_ip_on_launch = true
  availability_zone       = "${var.aws_region}a"

  tags = { Name = "sandbox-public-${terraform.workspace}" }
}

resource "aws_internet_gateway" "sandbox" {
  vpc_id = aws_vpc.sandbox.id

  tags = { Name = "sandbox-igw-${terraform.workspace}" }
}

resource "aws_route_table" "sandbox_public" {
  vpc_id = aws_vpc.sandbox.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.sandbox.id
  }

  tags = { Name = "sandbox-public-rt-${terraform.workspace}" }
}

resource "aws_route_table_association" "sandbox_public" {
  subnet_id      = aws_subnet.sandbox_public.id
  route_table_id = aws_route_table.sandbox_public.id
}

# ---- Security group: inbound deny-all, outbound allowlisted per ADR 0004 ----
resource "aws_security_group" "sandbox" {
  name        = "sandbox-sg-${terraform.workspace}"
  description = "Sandbox VM: no inbound, HTTP/HTTPS/DNS/specific outbound only"
  vpc_id      = aws_vpc.sandbox.id

  # Inbound: none (default deny)

  egress {
    description = "HTTPS out (broad, per ADR 0004)"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = var.allowed_egress_cidrs
  }

  egress {
    # Ubuntu APT mirrors are HTTP-only; needed for apt-get during bootstrap
    # and any future apt-get update/upgrade. Package signatures are still
    # GPG-verified, so HTTP doesn't weaken integrity.
    description = "HTTP out (Ubuntu APT mirrors)"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = var.allowed_egress_cidrs
  }

  egress {
    description = "DNS out (UDP)"
    from_port   = 53
    to_port     = 53
    protocol    = "udp"
    cidr_blocks = var.allowed_egress_cidrs
  }

  egress {
    description = "DNS out (TCP fallback)"
    from_port   = 53
    to_port     = 53
    protocol    = "tcp"
    cidr_blocks = var.allowed_egress_cidrs
  }

  egress {
    description = "Tailscale WireGuard (NAT traversal)"
    from_port   = 41641
    to_port     = 41641
    protocol    = "udp"
    cidr_blocks = var.allowed_egress_cidrs
  }

  # Open 5432 outbound only when the operator has actually populated
  # DATABASE_REPLICA_HOST in workspaces/<ws>.secrets.env. Avoids needing
  # to set the same FQDN in two places (tfvars + secrets.env).
  dynamic "egress" {
    for_each = var.database_replica_host != "" ? [1] : []
    content {
      description = "Prod Postgres replica"
      from_port   = 5432
      to_port     = 5432
      protocol    = "tcp"
      # Replica is public-access; SG restricts port only.
      cidr_blocks = ["0.0.0.0/0"]
    }
  }

  tags = { Name = "sandbox-sg-${terraform.workspace}" }
}

# ---- Optional KMS key for EBS encryption ----
data "aws_kms_alias" "ebs" {
  count = var.ebs_kms_key_alias != null ? 1 : 0
  name  = var.ebs_kms_key_alias
}

# ---- EC2 instance ----
resource "aws_instance" "sandbox" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.sandbox_public.id
  vpc_security_group_ids      = [aws_security_group.sandbox.id]
  associate_public_ip_address = true

  # ADR 0002 constraint 2: no IAM instance profile attached by default.
  # Operators can attach the SSM-only profile (see iam.tf) on demand
  # for break-glass access.
  iam_instance_profile = var.enable_ssm_break_glass ? aws_iam_instance_profile.ssm_break_glass.name : null

  metadata_options {
    http_tokens                 = "required" # IMDSv2 only
    http_put_response_hop_limit = 1
    http_endpoint               = "enabled"
  }

  root_block_device {
    volume_size = var.ebs_size_gb
    volume_type = "gp3"
    encrypted   = true
    kms_key_id  = var.ebs_kms_key_alias != null ? data.aws_kms_alias.ebs[0].target_key_arn : null
  }

  user_data = templatefile("${path.module}/../bootstrap.sh.tpl", {
    tailscale_auth_key = tailscale_tailnet_key.sandbox.key
    tailnet_hostname   = local.tailnet_hostname
    deepreel_repo_urls = jsonencode(var.deepreel_repo_urls)
    fun_repo_urls      = jsonencode(var.fun_repo_urls)
    skills_source_path = var.skills_source_path
    workspace_name     = terraform.workspace

    # Sandbox repo source — bootstrap clones this branch
    sandbox_repo_url = var.sandbox_repo_url
    sandbox_repo_ref = var.sandbox_repo_ref

    # Operator-supplied secrets (sensitive — also embedded in EC2 user-data
    # metadata, accessible only to principals with ec2:DescribeInstanceAttribute
    # in this account)
    aws_access_key_id         = aws_iam_access_key.sandbox.id
    aws_secret_access_key     = aws_iam_access_key.sandbox.secret
    aws_default_region        = var.aws_region
    gh_token_deepreel         = var.gh_token_deepreel
    gh_token_sandbox          = var.gh_token_sandbox
    anthropic_api_key         = var.anthropic_api_key
    database_replica_host     = var.database_replica_host
    database_replica_name     = var.database_replica_name
    database_replica_user     = var.database_replica_user
    database_replica_password = var.database_replica_password
  })

  # Force replacement on user-data change so a re-apply re-bootstraps cleanly.
  user_data_replace_on_change = true

  tags = { Name = "sandbox-${terraform.workspace}" }
}

resource "aws_eip" "sandbox" {
  instance = aws_instance.sandbox.id
  domain   = "vpc"

  tags = { Name = "sandbox-eip-${terraform.workspace}" }
}
