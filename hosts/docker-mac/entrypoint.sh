#!/bin/bash
# Runs as root on container start.
# Locks .env files, builds pi if needed, then drops to agent user.
# tmux runs as agent (so Pi's tmux-tools extension works).
# Admin window uses sudo bash for root access.

set -uo pipefail

# Copy secrets and .env files to container-local paths (not mounted volumes).
# Docker Desktop for Mac ignores chmod on mounted volumes (VirtioFS).
# Copying to /etc/devbox/locked/ makes real file permissions work.

mkdir -p /etc/devbox/locked
if [ -f /etc/devbox/secrets ]; then
  cp /etc/devbox/secrets /etc/devbox/locked/secrets
  chown root:root /etc/devbox/locked/secrets
  chmod 600 /etc/devbox/locked/secrets
fi

# Copy and lock project .env files
find /workspace -maxdepth 3 -name ".env*" \
  ! -name ".env.example" ! -name ".env.template" ! -name ".envrc" \
  -print0 2>/dev/null | while IFS= read -r -d '' f; do
    rel="${f#/workspace/}"
    dir="/etc/devbox/locked/projects/$(dirname "$rel")"
    mkdir -p "$dir"
    cp "$f" "$dir/$(basename "$f")"
    chown root:root "$dir/$(basename "$f")"
    chmod 600 "$dir/$(basename "$f")"
  done

# Mount an overlay to hide sensitive files from agent.
# Use bind mounts from empty files to shadow the originals.
# This hides them inside the container without touching the host.
mkdir -p /etc/devbox/empty
echo "# Access denied. Use 'sudo run' for commands needing credentials." > /etc/devbox/empty/placeholder

# Shadow /etc/devbox/secrets with the placeholder
mount --bind /etc/devbox/empty/placeholder /etc/devbox/secrets 2>/dev/null || true

# Shadow each .env file with the placeholder
find /workspace -maxdepth 3 -name ".env*" \
  ! -name ".env.example" ! -name ".env.template" ! -name ".envrc" \
  -print0 2>/dev/null | while IFS= read -r -d '' f; do
    mount --bind /etc/devbox/empty/placeholder "$f" 2>/dev/null || true
  done

# Fix git "dubious ownership" for mounted volumes (Mac UID mismatch)
git config --global --add safe.directory '*'
gosu agent git config --global --add safe.directory '*'

# Build pi from source if not already built
if [ -d /workspace/pi-mono ] && [ ! -f /workspace/pi-mono/packages/coding-agent/dist/cli.js ]; then
  echo "[devbox] Building pi from source..."
  cd /workspace/pi-mono
  gosu agent npm install
  gosu agent npm run build
  echo "[devbox] Pi built."
  cd /workspace
fi

# Docker Desktop for Mac: port forwards hit 0.0.0.0 but Pi binds 127.0.0.1.
# iptables NAT doesn't work on Mac's Docker VM.
# Use socat on offset ports: Docker forwards external:53692 → container:63692,
# socat listens on 0.0.0.0:63692 → forwards to 127.0.0.1:53692 where Pi listens.
# This avoids port conflicts since socat and Pi use different ports.
socat TCP-LISTEN:43692,bind=0.0.0.0,fork,reuseaddr TCP:127.0.0.1:53692 &
socat TCP-LISTEN:41455,bind=0.0.0.0,fork,reuseaddr TCP:127.0.0.1:1455 &
socat TCP-LISTEN:48085,bind=0.0.0.0,fork,reuseaddr TCP:127.0.0.1:8085 &
socat TCP-LISTEN:41121,bind=0.0.0.0,fork,reuseaddr TCP:127.0.0.1:51121 &

# Keep container alive — attach.sh creates the tmux session on first connect
exec gosu agent "$@"
