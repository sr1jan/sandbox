#!/bin/bash
# Install Oh My Pi (omp) for the 'agent' user. Idempotent.
#
# Installs only sandbox harness pieces:
#   - cred-guard / redactor / tmux-tools extensions
#   - dev-environment skill
#   - shared pattern JSONs
#
# Expects:
#   - agent user already exists
#   - curl, bash available
#   - $SANDBOX_DIR env var points at the sandbox repo root
#
# Optional env:
#   - AGENT_HOME   (default: /home/agent)
#   - AGENT_USER   (default: agent)
#   - OMP_INSTALL_URL (default: https://omp.sh/install)
#
# Usage (called from a host bootstrap):
#   SANDBOX_DIR=/path/to/sandbox bash agents/omp/install.sh

set -euo pipefail

: "${SANDBOX_DIR:?SANDBOX_DIR must point at the sandbox repo root}"
: "${AGENT_HOME:=/home/agent}"
: "${AGENT_USER:=agent}"
: "${OMP_INSTALL_URL:=https://omp.sh/install}"

echo "[omp-install] Setting up omp extensions, skills, and patterns..."

sudo -u "$AGENT_USER" mkdir -p \
  "$AGENT_HOME/.omp/agent/extensions" \
  "$AGENT_HOME/.omp/agent/skills" \
  "$AGENT_HOME/.omp/agent/patterns"

sudo cp "$SANDBOX_DIR/agents/omp/extensions/"*.ts "$AGENT_HOME/.omp/agent/extensions/"
sudo cp -r "$SANDBOX_DIR/agents/omp/skills/"* "$AGENT_HOME/.omp/agent/skills/"
sudo cp "$SANDBOX_DIR/shared/patterns/"*.json "$AGENT_HOME/.omp/agent/patterns/"
sudo chown -R "$AGENT_USER:$AGENT_USER" "$AGENT_HOME/.omp"

echo "[omp-install] Installing omp binary via $OMP_INSTALL_URL..."
# Official installer places the binary on the invoking user's PATH
# (typically ~/.local/bin/omp). Run as agent so ownership is correct.
if ! sudo -u "$AGENT_USER" bash -lc 'command -v omp >/dev/null'; then
  sudo -u "$AGENT_USER" bash -lc "curl -fsSL '$OMP_INSTALL_URL' | sh"
fi

# Official installer drops the binary on the agent's PATH (usually
# ~/.local/bin/omp). Move it to /opt/omp/omp so it cannot shadow the
# /usr/local/bin/omp sudo-run wrapper (agent PATH puts ~/.local/bin first).
sudo mkdir -p /opt/omp
OMP_SRC=""
if [ -x "$AGENT_HOME/.local/bin/omp" ] && [ ! -L "$AGENT_HOME/.local/bin/omp" ]; then
  OMP_SRC="$AGENT_HOME/.local/bin/omp"
elif OMP_SRC="$(sudo -u "$AGENT_USER" bash -lc 'command -v omp' 2>/dev/null)" && [ -n "$OMP_SRC" ] && [ -x "$OMP_SRC" ]; then
  :
else
  OMP_SRC=""
fi
[ -n "$OMP_SRC" ] || {
  echo "[omp-install] ERROR: omp binary not found after install" >&2
  exit 1
}
if [ "$OMP_SRC" != "/opt/omp/omp" ]; then
  sudo mv "$OMP_SRC" /opt/omp/omp
fi
sudo chmod 755 /opt/omp/omp
# Drop any leftover agent-local shadow so `omp` resolves to the wrapper.
sudo rm -f "$AGENT_HOME/.local/bin/omp"

# Install `omp` wrapper on PATH. Wraps via `sudo run` so provider API keys
# are sourced from /etc/devbox/locked/secrets at invocation time — never
# persisted in the agent's env or .bashrc. shared/sudoers.d/agent env_keep
# must preserve HERDR_* across that sudo so herdr-agent-state can report
# the pane (Agents sidebar).
#
# Built-in cursor provider: CURSOR_ACCESS_TOKEN (session JWT).
# Dashboard User API Key (crsr_…) needs exchange into ACCESS_TOKEN first;
# CURSOR_API_KEY alone is not enough for omp's built-in cursor client.
sudo tee /usr/local/bin/omp >/dev/null <<'EOF'
#!/bin/bash
exec sudo /usr/local/bin/run /opt/omp/omp "$@"
EOF
sudo chmod 755 /usr/local/bin/omp

# PATH addition for /home/agent/.local/bin (user-installed bins).
if ! sudo -u "$AGENT_USER" grep -q "/home/agent/.local/bin" "$AGENT_HOME/.bashrc" 2>/dev/null; then
  echo 'export PATH="/home/agent/.local/bin:$PATH"' | sudo tee -a "$AGENT_HOME/.bashrc" >/dev/null
  sudo chown "$AGENT_USER:$AGENT_USER" "$AGENT_HOME/.bashrc"
fi

echo "[omp-install] Done."
echo "[omp-install] Provider keys live in /etc/devbox/locked/secrets (sudo sync-secrets)."
echo "[omp-install] Sandbox extensions: cred-guard, redactor, tmux-tools."
echo "[omp-install] For Cursor models: set CURSOR_ACCESS_TOKEN (or exchange CURSOR_API_KEY)."
