#!/bin/bash
# sync-project-env.sh — ship one or more .env files from your local
# project dir to the sandbox VM at the path `shared/scripts/run`
# expects them.
#
# Run reads /etc/devbox/locked/projects/$REL/.env (and .env.local,
# .env.secrets, .env.development) where $REL is the cwd path under
# /workspace/. So for /workspace/core/backend, the per-project envs
# live at /etc/devbox/locked/projects/core/backend/.
#
# Usage:
#   ./sync-project-env.sh <local-dir> <vm-target>            # ship all .env* (except .env.example)
#   ./sync-project-env.sh <local-dir> <vm-target> <file>...  # ship specific files
#
# Examples:
#   ./sync-project-env.sh ~/work/deepreel/core/backend core/backend
#   ./sync-project-env.sh ~/work/deepreel/core/backend core/backend .env
#   ./sync-project-env.sh ~/work/deepreel/core/backend core/backend .env .env.dev
#   ./sync-project-env.sh ~/code/sandbox fun/sandbox
#
# Files stream over Tailscale SSH via stdin → sudo tee — never written
# to the local /tmp, never echoed to the operator's stdout. Final perms
# on the box: root:root 600.

set -euo pipefail

if [ $# -lt 2 ]; then
  cat >&2 <<USAGE
Usage: $0 <local-dir> <vm-target> [files...]
  local-dir   directory containing .env* files
  vm-target   path under /workspace/ on the box (e.g. 'core/backend' or 'fun/sandbox')
  files       optional .env filenames; default ships all .env* except .env.example
USAGE
  exit 1
fi

LOCAL_DIR="$1"
VM_TARGET="${2#/}"          # strip leading /
VM_TARGET="${VM_TARGET%/}"  # strip trailing /
shift 2
FILES=("$@")

[ -d "$LOCAL_DIR" ] || { echo "[sync-env] not a directory: $LOCAL_DIR" >&2; exit 1; }
case "$VM_TARGET" in
  ''|*..*) echo "[sync-env] invalid vm-target: '$VM_TARGET'" >&2; exit 1 ;;
esac

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TF_DIR="$ROOT/hosts/aws-ec2/terraform"
HOSTNAME="$(cd "$TF_DIR" && terraform output -raw tailnet_hostname)"

if [ ${#FILES[@]} -eq 0 ]; then
  while IFS= read -r f; do
    FILES+=("$(basename "$f")")
  done < <(find "$LOCAL_DIR" -maxdepth 1 -type f \
              \( -name '.env' -o -name '.env.*' \) \
              ! -name '.env.example' ! -name '.env.example.*' \
              ! -name '.env.bak' ! -name '.env.bak.*')
fi

if [ ${#FILES[@]} -eq 0 ]; then
  echo "[sync-env] no .env* files found in $LOCAL_DIR (and none specified)" >&2
  exit 1
fi

DEST_DIR="/etc/devbox/locked/projects/$VM_TARGET"

echo "[sync-env] target: $HOSTNAME:$DEST_DIR"
echo "[sync-env] files: ${FILES[*]}"

# Ensure dest dir exists with the right perms (700 down the chain).
tailscale ssh "ubuntu@$HOSTNAME" "
  set -e
  sudo install -d -m 700 -o root -g root '$DEST_DIR'
"

for f in "${FILES[@]}"; do
  src="$LOCAL_DIR/$f"
  if [ ! -f "$src" ]; then
    echo "[sync-env] skip $f (not found in $LOCAL_DIR)" >&2
    continue
  fi
  printf '[sync-env] sending %s ...' "$f"
  cat "$src" | tailscale ssh "ubuntu@$HOSTNAME" "
    sudo tee '$DEST_DIR/$f' >/dev/null
    sudo chown root:root '$DEST_DIR/$f'
    sudo chmod 600 '$DEST_DIR/$f'
  "
  echo " ok"
done

echo "[sync-env] done. Verify:"
echo "  tailscale ssh ubuntu@$HOSTNAME 'sudo ls -la $DEST_DIR/'"
