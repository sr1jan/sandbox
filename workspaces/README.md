# Workspaces

Each `*.tfvars` file here defines a distinct sandbox instance. The
filename (without extension) becomes the Terraform workspace name.

Workspaces are how the same IaC code produces different sandbox VMs
for different purposes — e.g., `deepreel-srijan-claude` (deepreel
work), `personal-srijan-claude` (personal projects), or, in the
future, per-dev stamps like `deepreel-alice-claude`.

## File conventions

| File | Committed? | Purpose |
|------|------------|---------|
| `<name>.tfvars` | yes | Workspace-specific Terraform variables |
| `<name>.secrets.env.example` | yes | Template for the secrets file |
| `<name>.secrets.env` | **no** (gitignored) | Real Tailscale OAuth creds, other TF_VAR secrets |

## Naming

`<org>-<owner>-<agent>`

Examples: `deepreel-srijan-claude`, `personal-srijan-pi`,
`deepreel-alice-claude` (future per-dev).

## Adding a new workspace

1. Copy an existing tfvars as template:
   ```bash
   cp deepreel-srijan-claude.tfvars my-workspace.tfvars
   cp deepreel-srijan-claude.secrets.env.example my-workspace.secrets.env
   ```

2. Edit `my-workspace.tfvars`: change `owner`, `vpc_cidr` (must not
   overlap with other workspaces' VPCs if they need to coexist),
   `tailscale_tailnet`, `deepreel_repo_urls`, etc.

3. Edit `my-workspace.secrets.env`: fill in the real Tailscale OAuth
   credentials, optional Anthropic API key, and DB replica creds.
   Setting `TF_VAR_database_replica_host` automatically opens outbound
   5432 in the SG. No GitHub token — auth on the VM is via SSH+GPG
   keypairs at `~/.sandbox-keys/`, shipped by `sync-ssh-keys.sh`.

4. Create the Terraform workspace, apply, and ship operator-supplied keys:
   ```bash
   cd ../hosts/aws-ec2/terraform
   terraform workspace new my-workspace
   set -a
   source ../../../workspaces/my-workspace.secrets.env
   set +a
   terraform apply -var-file=../../../workspaces/my-workspace.tfvars

   cd ..
   ./sync-ssh-keys.sh                       # ~/.sandbox-keys/ → VM
   ./power.sh sync                          # installs keys onto agent + retries clones
   ```

## Terraform state

Local state per workspace lives under `hosts/aws-ec2/terraform/
terraform.tfstate.d/<workspace>/` and is gitignored. Back up manually
(1Password, encrypted S3, etc.) if the state matters. A future migration
to S3+DynamoDB remote state is planned when going multi-dev.
