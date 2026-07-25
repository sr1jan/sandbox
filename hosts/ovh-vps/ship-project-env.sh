#!/bin/bash
# ship-project-env.sh — ship .env* files from a local project dir to
# /etc/devbox/locked/projects/<vm-target>/ on the VM (root:600).
# `run` sources them when invoked from /workspace/<vm-target>.
#
# Usage:
#   ./ship-project-env.sh <local-dir> <vm-target> [files...]
#   e.g. ./ship-project-env.sh ~/fun/myapp fun/myapp        # ships .env*
#        ./ship-project-env.sh ~/fun/myapp fun/myapp .env.production
#
# Files stream over Tailscale SSH via stdin → sudo tee — never written
# to local /tmp, never echoed.
set -euo pipefail

[ $# -ge 2 ] || { echo "Usage: $0 <local-dir> <vm-target> [files...]" >&2; exit 1; }
LOCAL_DIR="$1"; VM_TARGET="$2"; shift 2
[ -d "$LOCAL_DIR" ] || { echo "[ship-env] not a directory: $LOCAL_DIR" >&2; exit 1; }
source "$(cd "$(dirname "$0")" && pwd)/host.conf"

DEST="/etc/devbox/locked/projects/$VM_TARGET"
if [ $# -gt 0 ]; then
  FILES=("$@")
else
  FILES=()
  while IFS= read -r f; do FILES+=("$(basename "$f")"); done \
    < <(find "$LOCAL_DIR" -maxdepth 1 -name '.env*' -type f)
fi
[ ${#FILES[@]} -gt 0 ] || { echo "[ship-env] no .env* files in $LOCAL_DIR" >&2; exit 1; }

echo "[ship-env] target: $TAILNET_HOSTNAME:$DEST"
tailscale ssh "ubuntu@$TAILNET_HOSTNAME" "sudo install -d -m 700 -o root -g root '$DEST'"

for f in "${FILES[@]}"; do
  src="$LOCAL_DIR/$f"
  [ -f "$src" ] || { echo "[ship-env] skip $f (not found)" >&2; continue; }
  printf '[ship-env] sending %s ...' "$f"
  tailscale ssh "ubuntu@$TAILNET_HOSTNAME" "
    sudo tee '$DEST/$f' >/dev/null
    sudo chown root:root '$DEST/$f'
    sudo chmod 600 '$DEST/$f'
  " < "$src"
  echo " ok"
done
echo "[ship-env] done."
