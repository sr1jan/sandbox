#!/bin/bash
# sync-aws-keys.sh — populate the sandbox VM's /etc/devbox/locked/secrets
# with AWS_* keys from `terraform output`. Run after `terraform apply`.
#
# Usage:  ./hosts/aws-ec2/sync-aws-keys.sh
#
# Reads from the currently-selected terraform workspace (under
# hosts/aws-ec2/terraform/) and pipes through `tailscale ssh ubuntu@<host>
# sudo sync-secrets`. Values stream through the pipe — never echoed to
# stdout/stderr.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TF_DIR="$ROOT/hosts/aws-ec2/terraform"

cd "$TF_DIR"

WORKSPACE="$(terraform workspace show)"
if [ "$WORKSPACE" = "default" ]; then
  echo "sync-aws-keys: refusing to sync from 'default' workspace." >&2
  echo "  Switch with: terraform workspace select <name>" >&2
  exit 1
fi

HOSTNAME="$(terraform output -raw tailnet_hostname)"
REGION=""
WS_TFVARS="$ROOT/workspaces/$WORKSPACE.tfvars"
if [ -f "$WS_TFVARS" ]; then
  REGION="$(awk -F'=' '/^[[:space:]]*aws_region[[:space:]]*=/ { gsub(/[" ]/, "", $2); print $2; exit }' "$WS_TFVARS")"
fi

echo "[sync-aws-keys] workspace=$WORKSPACE host=$HOSTNAME region=${REGION:-<not set in tfvars>}"

{
  printf 'AWS_ACCESS_KEY_ID=%s\n'     "$(terraform output -raw iam_user_access_key_id)"
  printf 'AWS_SECRET_ACCESS_KEY=%s\n' "$(terraform output -raw iam_user_secret_access_key)"
  [ -n "$REGION" ] && printf 'AWS_DEFAULT_REGION=%s\n' "$REGION"
} | tailscale ssh "ubuntu@$HOSTNAME" 'sudo sync-secrets'

echo "[sync-aws-keys] Done."
echo "  Verify: tailscale ssh agent@$HOSTNAME 'sudo run aws sts get-caller-identity'"
