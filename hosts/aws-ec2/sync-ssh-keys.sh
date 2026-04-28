#!/bin/bash
# sync-ssh-keys.sh — ship the GitHub SSH + GPG keypairs from
# ~/.sandbox-keys/ on the operator's Mac to /etc/devbox/locked/keys/
# on the VM (root:600). Bootstrap and `power.sh sync` install them
# into ~agent/.ssh and ~agent/.gnupg.
#
# Usage:
#   ./sync-ssh-keys.sh                  # uses ~/.sandbox-keys
#   ./sync-ssh-keys.sh <local-dir>
#
# Files streamed: id_ed25519_personal[.pub], id_ed25519_deepreel[.pub],
# gpg_personal.asc, gpg_deepreel.asc. Optional: gpg_*.pub.asc are not
# shipped (pubs already live on GitHub).
#
# Like sync-project-env.sh, files stream over Tailscale SSH via stdin
# → sudo tee — never written to local /tmp, never echoed.

set -euo pipefail

LOCAL_DIR="${1:-$HOME/.sandbox-keys}"
[ -d "$LOCAL_DIR" ] || { echo "[sync-keys] not a directory: $LOCAL_DIR" >&2; exit 1; }

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TF_DIR="$ROOT/hosts/aws-ec2/terraform"
HOSTNAME="$(cd "$TF_DIR" && terraform output -raw tailnet_hostname)"

DEST=/etc/devbox/locked/keys
FILES=(
  id_ed25519_personal id_ed25519_personal.pub
  id_ed25519_deepreel id_ed25519_deepreel.pub
  gpg_personal.asc gpg_deepreel.asc
)

echo "[sync-keys] target: $HOSTNAME:$DEST"
echo "[sync-keys] source: $LOCAL_DIR"

tailscale ssh "ubuntu@$HOSTNAME" "
  set -e
  sudo install -d -m 700 -o root -g root '$DEST'
"

shipped=0
for f in "${FILES[@]}"; do
  src="$LOCAL_DIR/$f"
  if [ ! -f "$src" ]; then
    echo "[sync-keys] skip $f (not found in $LOCAL_DIR)" >&2
    continue
  fi
  printf '[sync-keys] sending %s ...' "$f"
  cat "$src" | tailscale ssh "ubuntu@$HOSTNAME" "
    sudo tee '$DEST/$f' >/dev/null
    sudo chown root:root '$DEST/$f'
    sudo chmod 600 '$DEST/$f'
  "
  echo " ok"
  shipped=$((shipped + 1))
done

if [ "$shipped" -eq 0 ]; then
  echo "[sync-keys] nothing shipped — check $LOCAL_DIR" >&2
  exit 1
fi

echo "[sync-keys] $shipped file(s) shipped. Now run:"
echo "  ./power.sh sync   # installs them onto agent"
