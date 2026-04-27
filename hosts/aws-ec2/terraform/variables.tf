variable "owner" {
  description = "Owner tag value, e.g. 'srijan'"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "ap-south-1"
}

variable "vpc_cidr" {
  description = "CIDR for the dedicated sandbox VPC (must not overlap prod)"
  type        = string
  default     = "10.100.0.0/16"
}

variable "subnet_cidr" {
  description = "CIDR for the sandbox public subnet"
  type        = string
  default     = "10.100.1.0/24"
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.large"
}

variable "ebs_size_gb" {
  description = "Root EBS volume size in GB"
  type        = number
  default     = 40
}

variable "ebs_kms_key_alias" {
  description = "KMS key alias (e.g., 'alias/sandbox-ebs') for EBS encryption. If null, uses AWS-managed aws/ebs."
  type        = string
  default     = null
}

variable "tailscale_oauth_client_id" {
  description = "Tailscale OAuth client ID for provisioning ephemeral auth keys"
  type        = string
  sensitive   = true
}

variable "tailscale_oauth_client_secret" {
  description = "Tailscale OAuth client secret"
  type        = string
  sensitive   = true
}

variable "tailscale_tailnet" {
  description = "Tailscale tailnet name, e.g. 'deepreel.com'"
  type        = string
}

variable "tailscale_tag" {
  description = "Tailscale tag for the sandbox VM (must be pre-created in the tailnet ACL)"
  type        = string
  default     = "tag:claude-sandbox"
}

variable "allowed_egress_cidrs" {
  description = "CIDRs for egress security-group rules. Broad HTTPS egress per ADR 0004."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "prod_replica_endpoint" {
  description = "Prod read-replica endpoint FQDN the sandbox VM may reach on 5432. null to disable."
  type        = string
  default     = null
}

variable "cloudwatch_log_group_arns" {
  description = "CloudWatch log group ARNs the sandbox IAM user may read. [] = all groups."
  type        = list(string)
  default     = []
}

variable "enable_ssm_break_glass" {
  description = "When true, attach the SSM-only IAM instance profile at create time (see ADR 0003). Default: false — attach on demand."
  type        = bool
  default     = false
}

variable "deepreel_repo_urls" {
  description = "List of git URLs to clone into /workspace/core/ during bootstrap"
  type        = list(string)
  default     = []
}

variable "skills_source_path" {
  description = "Absolute path on the VM to skills dir to symlink into agent's ~/.claude/skills/. Empty string to skip."
  type        = string
  default     = ""
}

# ---- Sandbox repo (clone source for bootstrap) ----

variable "sandbox_repo_url" {
  description = "HTTPS URL of the sandbox repo to clone on the VM at bootstrap time."
  type        = string
  default     = "https://github.com/sr1jan/sandbox.git"
}

variable "sandbox_repo_ref" {
  description = "Git ref (branch/tag/sha) to clone. Set to a feature branch when iterating; flip to main once merged."
  type        = string
  default     = "main"
}

# ---- Operator-supplied secrets (passed via user-data → bootstrap → /etc/devbox/locked/secrets) ----
# All sensitive. Provide via TF_VAR_* in workspaces/<name>.secrets.env (gitignored).
# These land on the VM in the global secrets file, sourced by `sudo run`.

variable "gh_token_deepreel" {
  description = "GitHub PAT scoped to deepreel/* private repos (read). Used by bootstrap for repo clone and by agent runtime via gh CLI. Empty string disables private-repo clone."
  type        = string
  sensitive   = true
  default     = ""
}

variable "gh_token_sandbox" {
  description = "Optional GitHub PAT for sr1jan/sandbox (e.g. agent self-modifies infra). Not required for v1 since sandbox repo is public."
  type        = string
  sensitive   = true
  default     = ""
}

variable "anthropic_api_key" {
  description = "Anthropic API key. Optional — Claude Code can device-flow login on first run if empty."
  type        = string
  sensitive   = true
  default     = ""
}

variable "database_replica_host" {
  description = "Prod read-replica DB host. Required only if prod_replica_endpoint is set."
  type        = string
  sensitive   = true
  default     = ""
}

variable "database_replica_name" {
  description = "Prod read-replica DB name."
  type        = string
  sensitive   = true
  default     = ""
}

variable "database_replica_user" {
  description = "Prod read-replica DB user (read-only role)."
  type        = string
  sensitive   = true
  default     = ""
}

variable "database_replica_password" {
  description = "Prod read-replica DB password."
  type        = string
  sensitive   = true
  default     = ""
}
