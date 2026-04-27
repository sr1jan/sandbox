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

# Install `pi` as a real binary on PATH (works in interactive AND
# non-interactive shells). Wraps via `sudo run` so ANTHROPIC_API_KEY (and
# any other creds) are sourced from /etc/devbox/locked/secrets at invocation
# time — never persisted in the agent's env or .bashrc.
sudo tee /usr/local/bin/pi >/dev/null <<EOF
#!/bin/bash
exec sudo /usr/local/bin/run node $PI_BIN "\$@"
EOF
sudo chmod 755 /usr/local/bin/pi

# PATH addition for /home/agent/.local/bin (user-installed pip/cargo bins).
# Distinct concern from the pi alias above; safe to keep.
if ! sudo -u "$AGENT_USER" grep -q "/home/agent/.local/bin" "$AGENT_HOME/.bashrc" 2>/dev/null; then
  echo 'export PATH="/home/agent/.local/bin:$PATH"' | sudo tee -a "$AGENT_HOME/.bashrc" >/dev/null
  sudo chown "$AGENT_USER:$AGENT_USER" "$AGENT_HOME/.bashrc"
fi

echo "[pi-install] Done."
echo "[pi-install] Pi reads ANTHROPIC_API_KEY from /etc/devbox/locked/secrets via 'sudo run'."
echo "[pi-install] Populate it with: echo 'ANTHROPIC_API_KEY=...' | sudo sync-secrets"
