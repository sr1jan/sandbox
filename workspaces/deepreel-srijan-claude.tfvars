owner      = "srijan"
aws_region = "ap-south-1"

# Dedicated VPC (no peering to default VPC where deepreel prod lives)
vpc_cidr    = "10.100.0.0/16"
subnet_cidr = "10.100.1.0/24"

instance_type = "t4g.large"   # Graviton ARM (matches local M1 Mac arch; ~20% cheaper than t3.large)
ebs_size_gb   = 40

# Leave null to use AWS-managed aws/ebs key, or set to "alias/sandbox-ebs"
# after creating a customer-managed key with logged usage.
ebs_kms_key_alias = null

# Tailscale
tailscale_tailnet = "deepreel.com"         # TODO: replace with your actual tailnet name
tailscale_tag     = "tag:claude-sandbox"

# tailscale_oauth_client_id and tailscale_oauth_client_secret come from
# deepreel-srijan-claude.secrets.env (loaded via TF_VAR_ env vars).

# Prod replica (already publicly accessible per spec §3). Setting this
# opens 5432 outbound in the SG. Fill in the actual FQDN before apply.
prod_replica_endpoint = null   # TODO: e.g. "<host>.<region>.rds.amazonaws.com"

# CloudWatch log group ARNs the sandbox IAM user is allowed to read.
# Empty list = scope to "*" (simplest for v1; tighten later).
cloudwatch_log_group_arns = [
  # "arn:aws:logs:ap-south-1:<account-id>:log-group:/ecs/deepreel-backend:*",
]

# Deepreel repos to clone into /workspace/core/ during bootstrap.
# Empty list = nothing is cloned (useful for first provisioning test).
deepreel_repo_urls = [
  # "git@github.com:deepreel/backend.git",
  # "git@github.com:deepreel/seo-content-agent.git",
  # "git@github.com:deepreel/frontend.git",
  # "git@github.com:deepreel/skills.git",
]

# Path on the VM to the skills dir (one of the deepreel_repo_urls
# entries should land here). If empty, no skills are symlinked into
# the agent's ~/.claude/skills/.
skills_source_path = "/workspace/core/skills"

# ADR 0003 default: attach SSM-only profile only on demand.
enable_ssm_break_glass = false
