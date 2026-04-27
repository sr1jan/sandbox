owner      = "srijan"
aws_region = "ap-south-1"

# Pin sandbox repo to the feature branch until v1 is merged. Flip back to
# "main" (default) once feat/yolo-sandbox-v1 lands.
sandbox_repo_ref = "feat/yolo-sandbox-v1"

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

# Prod replica access is gated automatically: when DATABASE_REPLICA_HOST
# is set in the workspace's .secrets.env, the SG opens outbound 5432 and
# the deepreel-db skill can reach it. Nothing to set here.

# Deepreel repos to clone into /workspace/core/ during bootstrap.
# Use "owner/name" form (preferred — bootstrap calls `gh repo clone`).
# CloudWatch log group ARNs the sandbox IAM user is allowed to read.
# Empty list = scope to "*" (simplest for v1; tighten later).
cloudwatch_log_group_arns = [
  # "arn:aws:logs:ap-south-1:<account-id>:log-group:/ecs/deepreel-backend:*",
]

# Work repos → /workspace/core/. "owner/name" form, gh repo clone.
deepreel_repo_urls = [
  "deepreel/backend",
  "deepreel/deepreel-frontend",
  "deepreel/deepreel-web",
  "deepreel/skills",
]

# Personal repos → /workspace/fun/. Same form. Use `tx fun` to launch
# the personal-projects tmux layout.
fun_repo_urls = [
  "sr1jan/sandbox",
]

# Path on the VM to the skills dir (one of the deepreel_repo_urls
# entries should land here). If empty, no skills are symlinked into
# the agent's ~/.claude/skills/.
skills_source_path = "/workspace/core/skills"

# ADR 0003 default: attach SSM-only profile only on demand.
enable_ssm_break_glass = false
