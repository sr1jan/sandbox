#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# Check secrets file
if [ ! -f secrets ]; then
  echo "No secrets file found. Creating from template..."
  cp secrets.example secrets
  echo "Edit hosts/docker-mac/secrets with your CLI credentials, then run again."
  exit 1
fi

# Prompt for Anthropic API key if not set
if [ -z "${ANTHROPIC_API_KEY:-}" ]; then
  echo -n "ANTHROPIC_API_KEY: "
  read -rs ANTHROPIC_API_KEY
  echo ""
  export ANTHROPIC_API_KEY
fi

echo "Building devbox..."
docker compose build

echo "Starting devbox..."
docker compose up -d

echo ""
echo "Devbox running. Connect with:"
echo "  docker exec -it devbox bash          # agent shell"
echo "  docker exec -u root -it devbox bash  # admin shell (manage credentials)"
echo ""
echo "Or use tmuxinator:"
echo "  tmuxinator start fun-sandbox"
