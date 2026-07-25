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
#   - PI_PACKAGE   (default: @earendil-works/pi-coding-agent)
#
# Usage (called from a host bootstrap):
#   SANDBOX_DIR=/path/to/sandbox bash agents/pi/install.sh

set -euo pipefail

: "${SANDBOX_DIR:?SANDBOX_DIR must point at the sandbox repo root}"
: "${AGENT_HOME:=/home/agent}"
: "${AGENT_USER:=agent}"
: "${PI_PACKAGE:=@earendil-works/pi-coding-agent}"

echo "[pi-install] Setting up Pi extensions, skills, and patterns..."

sudo -u "$AGENT_USER" mkdir -p \
  "$AGENT_HOME/.pi/agent/extensions" \
  "$AGENT_HOME/.pi/agent/skills" \
  "$AGENT_HOME/.pi/agent/patterns"

sudo cp "$SANDBOX_DIR/agents/pi/extensions/"*.ts "$AGENT_HOME/.pi/agent/extensions/"
sudo cp -r "$SANDBOX_DIR/agents/pi/skills/"* "$AGENT_HOME/.pi/agent/skills/"
sudo cp "$SANDBOX_DIR/shared/patterns/"*.json "$AGENT_HOME/.pi/agent/patterns/"
sudo chown -R "$AGENT_USER:$AGENT_USER" "$AGENT_HOME/.pi"

echo "[pi-install] Installing $PI_PACKAGE into /opt/pi..."
sudo mkdir -p /opt/pi
if [ ! -f /opt/pi/package.json ]; then
  ( cd /opt/pi && sudo npm init -y >/dev/null )
fi
( cd /opt/pi && sudo npm install "$PI_PACKAGE" )

PI_BIN="/opt/pi/node_modules/.bin/pi"
[ -x "$PI_BIN" ] || { echo "[pi-install] ERROR: $PI_BIN not found after install" >&2; exit 1; }

# Install `pi` wrapper on PATH. Wraps via `sudo run` so provider API keys
# are sourced from /etc/devbox/locked/secrets at invocation time — never
# persisted in the agent's env or .bashrc. Pi's built-in providers pick
# them up from the process env:
#   DEEPSEEK_API_KEY   (deepseek — PAYG default)
#   ZAI_API_KEY        (zai — GLM Coding Plan endpoint)
#   KIMI_API_KEY       (kimi-coding — Kimi membership endpoint)
#   MOONSHOT_API_KEY   (moonshotai — Moonshot PAYG API)
#   OPENROUTER_API_KEY (openrouter — BYOK fallback router)
#   ANTHROPIC_API_KEY  (anthropic — optional escalation)
sudo tee /usr/local/bin/pi >/dev/null <<EOF
#!/bin/bash
exec sudo /usr/local/bin/run $PI_BIN "\$@"
EOF
sudo chmod 755 /usr/local/bin/pi

# PATH addition for /home/agent/.local/bin (user-installed pip/cargo bins).
# Distinct concern from the pi wrapper above; safe to keep.
if ! sudo -u "$AGENT_USER" grep -q "/home/agent/.local/bin" "$AGENT_HOME/.bashrc" 2>/dev/null; then
  echo 'export PATH="/home/agent/.local/bin:$PATH"' | sudo tee -a "$AGENT_HOME/.bashrc" >/dev/null
  sudo chown "$AGENT_USER:$AGENT_USER" "$AGENT_HOME/.bashrc"
fi

echo "[pi-install] Done."
echo "[pi-install] Provider keys live in /etc/devbox/locked/secrets (sudo sync-secrets)."
echo "[pi-install] Models: Pi's built-in catalog (zai / kimi-coding / deepseek / moonshotai / openrouter)."
