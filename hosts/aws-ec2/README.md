# AWS EC2 host

Provisions a YOLO-mode coding-agent sandbox VM in AWS, following ADR 0002's
"done carefully" constraints. Access is via Tailscale only; SSM is a
break-glass path.

See [design spec](../../docs/superpowers/specs/2026-04-24-yolo-sandbox-design.md)
for the full architecture. Key constraints:

- Dedicated VPC with no peering to prod (ADR 0002 constraint 1)
- No IAM instance profile by default (ADR 0002 constraint 2); SSM
  break-glass profile attached on demand only
- CloudWatch reader uses a hand-written policy with explicit Deny on
  writes (ADR 0002 constraint 3)
- IMDSv2 required with hop-limit 1 (ADR 0002 constraint 4)
- Broad HTTPS egress + DNS + specific prod replica port;
  everything else denied (ADR 0004)

## Prerequisites

- AWS CLI configured for the deepreel account with permissions to
  manage VPC, EC2, IAM, and SSM resources (admin or a scoped-down
  provisioning role)
- Terraform >= 1.6 (OpenTofu 1.7+ also works)
- A Tailscale tailnet with an OAuth client configured
  (Admin Console → Settings → OAuth Clients → New client; scopes:
  `auth_keys`, `devices`)
- The tag you'll use (default `tag:claude-sandbox`) must be pre-created
  in the tailnet ACL
- A workspace tfvars file under `../../workspaces/<workspace>.tfvars`
  and a matching `<workspace>.secrets.env` (gitignored) with the
  Tailscale OAuth credentials, optional Anthropic key, and prod-replica DB creds
- Two GitHub SSH+GPG keypairs at `~/.sandbox-keys/` (one for personal,
  one for work) with the public halves registered on the matching
  GitHub accounts. `./sync-ssh-keys.sh` ships them to the VM after
  `terraform apply`. Without these, the bootstrap can't clone any
  private repos via the per-identity SSH host aliases

## First-time setup

```bash
cd hosts/aws-ec2/terraform
terraform init
terraform workspace new <workspace-name>   # e.g. deepreel-srijan-claude
```

Load workspace secrets (Tailscale OAuth) into environment:

```bash
set -a
source ../../../workspaces/<workspace-name>.secrets.env
set +a
```

Plan and apply:

```bash
terraform plan  -var-file=../../../workspaces/<workspace-name>.tfvars
terraform apply -var-file=../../../workspaces/<workspace-name>.tfvars
```

Wait ~3-5 minutes for the VM to bootstrap (installs packages, joins
tailnet, installs Claude Code, attempts repo clones). Then ship the
operator-supplied keys + reconcile:

```bash
cd ..
./sync-ssh-keys.sh    # ~/.sandbox-keys/ → /etc/devbox/locked/keys/
./power.sh sync       # installs keys onto agent + retries any clones bootstrap missed
```

For subsequent rebuilds, `./rebuild.sh` does `terraform apply` + the
two sync steps + a smoke test in one command.

Progress:

```bash
# Watch the tailnet admin console — the new node should appear.
# If you need to see bootstrap logs:
./connect.sh --user ubuntu
sudo tail -f /var/log/sandbox-bootstrap.log
```

## Connecting

After bootstrap completes:

```bash
./connect.sh                      # SSH as ubuntu (admin)
./connect.sh --user agent         # SSH as the sandboxed agent user
./connect.sh --workspace <name>   # to a specific workspace's VM
```

Your Mac must have Tailscale running and be logged into the same
tailnet as the VM.

## Break-glass via SSM

If Tailscale access fails (daemon down, key expired, etc.):

```bash
# Attach the SSM-only IAM profile:
aws ec2 associate-iam-instance-profile \
  --instance-id  $(terraform output -raw instance_id) \
  --iam-instance-profile Name=$(terraform output -raw ssm_break_glass_profile_name)

# Start the session:
aws ssm start-session --target $(terraform output -raw instance_id)

# ...fix whatever's broken...
exit

# Detach the profile when done:
aws ec2 disassociate-iam-instance-profile \
  --association-id $(aws ec2 describe-iam-instance-profile-associations \
    --filters Name=instance-id,Values=$(terraform output -raw instance_id) \
    --query 'IamInstanceProfileAssociations[0].AssociationId' --output text)
```

## Post-apply setup

The bootstrap auto-templates AWS keys + Anthropic key + DB creds from
the workspace's `TF_VAR_*` into `/etc/devbox/locked/secrets` (root:600)
via `sync-secrets`. There's no manual edit required for those.

Operator-only material that the repo doesn't carry — ship after apply:

```bash
./sync-ssh-keys.sh                         # GitHub SSH+GPG keys
./sync-project-env.sh <local-dir> <vm-target>  # per-project .env files (repeat per project)
./power.sh sync                            # installs everything onto agent
```

To rotate AWS keys later, use `./sync-aws-keys.sh` (no terraform apply).
For non-tfvars secrets, edit on the box: `sudo sync-secrets < new-keyvals`.

## Teardown

```bash
terraform destroy -var-file=../../../workspaces/<workspace-name>.tfvars
```

Then verify in the AWS console that no `sandbox-*` resources remain.
If any orphans, that's the spec's acceptance criterion — file a
follow-up.
