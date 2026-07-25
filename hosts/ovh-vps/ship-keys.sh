#!/bin/bash
# ship-keys.sh — ship the personal GitHub SSH + GPG keypair from
# ~/.sandbox-keys/ on the operator's Mac to /etc/devbox/locked/keys/
# on the VM (root:600). sync.sh installs them onto agent.
#
# Usage:
#   ./ship-keys.sh                  # uses ~/.sandbox-keys
#   ./ship-keys.sh <local-dir>
#
# Files stream over Tailscale SSH via stdin → sudo tee — never written
# to local /tmp, never echoed.
set -euo pipefail

LOCAL_DIR="${1:-$HOME/.sandbox-keys}"
[ -d "$LOCAL_DIR" ] || { echo "[ship-keys] not a directory: $LOCAL_DIR" >&2; exit 1; }
source "$(cd "$(dirname "$0")" && pwd)/host.conf"

DEST=/etc/devbox/locked/keys
FILES=(id_ed25519_personal id_ed25519_personal.pub gpg_personal.asc)

echo "[ship-keys] target: $TAILNET_HOSTNAME:$DEST"
tailscale ssh "ubuntu@$TAILNET_HOSTNAME" "sudo install -d -m 700 -o root -g root '$DEST'"

shipped=0
for f in "${FILES[@]}"; do
  src="$LOCAL_DIR/$f"
  [ -f "$src" ] || { echo "[ship-keys] skip $f (not found)" >&2; continue; }
  printf '[ship-keys] sending %s ...' "$f"
  tailscale ssh "ubuntu@$TAILNET_HOSTNAME" "
    sudo tee '$DEST/$f' >/dev/null
    sudo chown root:root '$DEST/$f'
    sudo chmod 600 '$DEST/$f'
  " < "$src"
  echo " ok"
  shipped=$((shipped + 1))
done

[ "$shipped" -gt 0 ] || { echo "[ship-keys] nothing shipped — check $LOCAL_DIR" >&2; exit 1; }
echo "[ship-keys] $shipped file(s) shipped. Now run: ./sync.sh"
