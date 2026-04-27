#!/bin/bash
# power.sh — start/stop/status the sandbox EC2 for the currently
# selected terraform workspace.
#
# Usage:
#   ./power.sh                # status (default)
#   ./power.sh status
#   ./power.sh stop           # stop EC2 (compute $0/hr, EBS still bills)
#   ./power.sh start          # start EC2 (Tailscale auto-reconnects)
#
# Cost note: stopping saves the EC2 hourly rate (~$0.045/hr for t4g.large)
# but EBS keeps billing (~$3.65/mo for 40GB gp3) and the public IPv4
# also keeps billing (~$3.65/mo, AWS policy since Feb 2024). Stopping
# overnight on weekdays cuts compute by ~75%.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TF_DIR="$ROOT/hosts/aws-ec2/terraform"
ACTION="${1:-status}"

WORKSPACE="$(cd "$TF_DIR" && terraform workspace show)"
if [ "$WORKSPACE" = "default" ]; then
  echo "power.sh: refusing to operate on 'default' workspace." >&2
  echo "  Switch with: terraform workspace select <name>" >&2
  exit 1
fi

WS_TFVARS="$ROOT/workspaces/$WORKSPACE.tfvars"
REGION="$(awk -F'=' '/^[[:space:]]*aws_region[[:space:]]*=/ { gsub(/[" ]/, "", $2); print $2; exit }' "$WS_TFVARS")"
INSTANCE_ID="$(cd "$TF_DIR" && terraform output -raw instance_id)"
HOSTNAME="$(cd "$TF_DIR" && terraform output -raw tailnet_hostname)"

case "$ACTION" in
  start)
    echo "[power] Starting $INSTANCE_ID in $REGION..."
    aws ec2 start-instances \
      --instance-ids "$INSTANCE_ID" --region "$REGION" --output table \
      --query 'StartingInstances[*].[InstanceId,CurrentState.Name,PreviousState.Name]'
    echo "[power] Tailscale daemon auto-reconnects within ~30s."
    echo "[power] Verify with: tailscale ping $HOSTNAME"
    ;;
  stop)
    echo "[power] Stopping $INSTANCE_ID in $REGION..."
    aws ec2 stop-instances \
      --instance-ids "$INSTANCE_ID" --region "$REGION" --output table \
      --query 'StoppingInstances[*].[InstanceId,CurrentState.Name,PreviousState.Name]'
    echo "[power] EC2 hourly compute is now \$0/hr."
    echo "[power] EBS (~\$3.65/mo) and EIP (~\$3.65/mo) still bill while stopped."
    ;;
  status)
    aws ec2 describe-instances \
      --instance-ids "$INSTANCE_ID" --region "$REGION" --output table \
      --query 'Reservations[*].Instances[*].[InstanceId,State.Name,InstanceType,LaunchTime,PrivateIpAddress]'
    ;;
  *)
    echo "Usage: $0 {start|stop|status}" >&2
    exit 1
    ;;
esac
