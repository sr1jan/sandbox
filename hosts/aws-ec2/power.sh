#!/bin/bash
# power.sh — start/stop/status the sandbox EC2 for the currently
# selected terraform workspace.
#
# Usage:
#   ./power.sh                # status (default)
#   ./power.sh status
#   ./power.sh stop           # stop EC2 (compute $0/hr, EBS still bills)
#   ./power.sh start          # start EC2 (Tailscale auto-reconnects)
#   ./power.sh sync           # reconcile box without replacing it:
#                             #  - git pull /opt/sandbox (latest scripts)
#                             #  - reinstall scripts + tmuxinator configs
#                             #  - clone any tfvars repos missing from
#                             #    /workspace/{core,fun}/
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
  sync)
    echo "[power] Pulling latest /opt/sandbox..."
    tailscale ssh "ubuntu@$HOSTNAME" 'cd /opt/sandbox && sudo git pull --ff-only 2>&1 | tail -3'

    echo "[power] Re-installing shared scripts + tmuxinator configs..."
    tailscale ssh "ubuntu@$HOSTNAME" '
      set -e
      for s in run lock-env unlock-env sync-secrets with_creds tx; do
        sudo install -m 755 /opt/sandbox/shared/scripts/$s /usr/local/bin/$s
      done
      sudo -u agent mkdir -p /home/agent/.config/tmuxinator
      for cfg in /opt/sandbox/shared/tmuxinator/*.yml; do
        sudo install -m 644 -o agent -g agent "$cfg" "/home/agent/.config/tmuxinator/$(basename "$cfg")"
      done
      for f in .tmux.conf .tmux.conf.local; do
        sudo install -m 644 -o agent -g agent "/opt/sandbox/shared/dotfiles/tmux/$f" "/home/agent/$f"
      done
    '

    echo "[power] Cloning any missing repos from current tfvars..."
    CORE_REPOS="$(cd "$TF_DIR" && terraform output -json deepreel_repo_urls | jq -r '.[]')"
    FUN_REPOS="$(cd "$TF_DIR" && terraform output -json fun_repo_urls | jq -r '.[]')"
    {
      printf 'CORE %s\n' $CORE_REPOS
      printf 'FUN %s\n' $FUN_REPOS
    } | tailscale ssh "ubuntu@$HOSTNAME" '
      while read -r bucket repo; do
        [ -z "$repo" ] && continue
        case "$bucket" in
          CORE) target=/workspace/core ;;
          FUN)  target=/workspace/fun ;;
        esac
        case "$repo" in
          https://github.com/*)
            ownername="$(echo "$repo" | sed -E "s|^https://github.com/||;s|\.git$||")" ;;
          *)
            ownername="$repo" ;;
        esac
        repo_name="$(basename "$ownername")"
        if [ ! -d "$target/$repo_name" ]; then
          echo "  cloning $ownername → $target/$repo_name"
          sudo mkdir -p "$target" && sudo chown agent:agent "$target"
          sudo -u agent gh repo clone "$ownername" "$target/$repo_name" \
            || echo "  warning: failed to clone $ownername (token may lack access)"
        else
          echo "  skip $ownername (already cloned)"
        fi
      done
    '
    echo "[power] Sync complete."
    ;;
  *)
    echo "Usage: $0 {start|stop|status|sync}" >&2
    exit 1
    ;;
esac
