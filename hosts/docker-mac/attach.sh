#!/bin/bash
# Attach to the devbox sandbox from Ghostty (NOT from inside tmux).
# Starts container if needed, then attaches to tmux inside it.
#
# Usage: ./attach.sh

set -euo pipefail

# Detach from any existing tmux session first
if [ -n "${TMUX:-}" ]; then
  echo "You're inside tmux. Detaching first..."
  # Can't nest tmux — detach and re-run from bare shell
  echo "Run this from a bare Ghostty shell (Cmd+T for new tab), not from inside tmux."
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# Check secrets
if [ ! -f secrets ]; then
  cp secrets.example secrets
  echo "Edit hosts/docker-mac/secrets with your CLI credentials, then run again."
  exit 1
fi

# Prompt for API key if not set
if [ -z "${ANTHROPIC_API_KEY:-}" ]; then
  if [ -f ~/.config/anthropic/api_key ]; then
    export ANTHROPIC_API_KEY="$(cat ~/.config/anthropic/api_key)"
  else
    echo -n "ANTHROPIC_API_KEY: "
    read -rs ANTHROPIC_API_KEY
    echo ""
    export ANTHROPIC_API_KEY
  fi
fi

# Start container
docker compose up -d 2>/dev/null

# Attach to agent's tmux session, or create it if it doesn't exist
docker exec -it -u agent devbox bash -c '
  if tmux has-session -t dev 2>/dev/null; then
    tmux attach -t dev
  else
    tmux new-session -d -s dev -n admin -c /workspace
    tmux send-keys -t dev:admin "sudo bash" Enter
    tmux new-window -t dev -n AISpotlight -c /workspace/AISpotlight
    tmux split-window -t dev:AISpotlight -v -c /workspace/AISpotlight
    tmux send-keys -t dev:AISpotlight.0 "pi" Enter
    tmux select-window -t dev:AISpotlight
    tmux attach -t dev
  fi
'
