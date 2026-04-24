#!/bin/bash
# Install Pi coding agent for the 'agent' user. Idempotent.
#
# Expects:
#   - agent user already exists
#   - Node.js 22, git, curl available
#   - $SANDBOX_DIR env var points at the sandbox repo root
#
# Optional env:
#   - AGENT_HOME   (default: /home/agent)
#   - AGENT_USER   (default: agent)
#
# Usage (called from a host bootstrap):
#   SANDBOX_DIR=/path/to/sandbox bash agents/pi/install.sh

set -euo pipefail

: "${SANDBOX_DIR:?SANDBOX_DIR must point at the sandbox repo root}"
: "${AGENT_HOME:=/home/agent}"
: "${AGENT_USER:=agent}"
: "${PI_PROJECTS_DIR:=$HOME/projects}"

echo "[pi-install] Setting up Pi extensions, skills, and patterns..."

sudo -u "$AGENT_USER" mkdir -p \
  "$AGENT_HOME/.pi/agent/extensions" \
  "$AGENT_HOME/.pi/agent/skills" \
  "$AGENT_HOME/.pi/agent/patterns"

sudo cp "$SANDBOX_DIR/agents/pi/extensions/"*.ts "$AGENT_HOME/.pi/agent/extensions/"
sudo cp -r "$SANDBOX_DIR/agents/pi/skills/"* "$AGENT_HOME/.pi/agent/skills/"
sudo cp "$SANDBOX_DIR/shared/patterns/"*.json "$AGENT_HOME/.pi/agent/patterns/"
sudo chown -R "$AGENT_USER:$AGENT_USER" "$AGENT_HOME/.pi"

echo "[pi-install] Cloning and building pi-mono..."
mkdir -p "$PI_PROJECTS_DIR"
if [ ! -d "$PI_PROJECTS_DIR/pi-mono" ]; then
  git clone https://github.com/badlogic/pi-mono.git "$PI_PROJECTS_DIR/pi-mono"
fi
( cd "$PI_PROJECTS_DIR/pi-mono" && npm install && npm run build )

PI_BIN="$PI_PROJECTS_DIR/pi-mono/packages/coding-agent/dist/cli/index.js"

if ! sudo -u "$AGENT_USER" grep -q "alias pi=" "$AGENT_HOME/.bashrc" 2>/dev/null; then
  echo "alias pi=\"node $PI_BIN\"" | sudo tee -a "$AGENT_HOME/.bashrc" >/dev/null
  echo 'export PATH="/home/agent/.local/bin:$PATH"' | sudo tee -a "$AGENT_HOME/.bashrc" >/dev/null
  sudo chown "$AGENT_USER:$AGENT_USER" "$AGENT_HOME/.bashrc"
fi

# ANTHROPIC_API_KEY in agent's shell — Pi needs this to authenticate.
# Skipped silently if the env var isn't set at install time; admin can
# add it manually to /home/agent/.bashrc or /etc/devbox/secrets later.
if [ -n "${ANTHROPIC_API_KEY:-}" ] && ! sudo -u "$AGENT_USER" grep -q ANTHROPIC_API_KEY "$AGENT_HOME/.bashrc" 2>/dev/null; then
  echo "export ANTHROPIC_API_KEY=\"$ANTHROPIC_API_KEY\"" | sudo tee -a "$AGENT_HOME/.bashrc" >/dev/null
  sudo chown "$AGENT_USER:$AGENT_USER" "$AGENT_HOME/.bashrc"
fi

echo "[pi-install] Done."
