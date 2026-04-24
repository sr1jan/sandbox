#!/bin/bash
# Install Claude Code for the 'agent' user. Idempotent.
#
# Expects:
#   - $SANDBOX_DIR env var points at the sandbox repo root
#   - agent user exists
#   - Node.js 22 available
#   - jq available (used by the hooks)
#
# Optional env:
#   - AGENT_HOME           (default: /home/agent)
#   - AGENT_USER           (default: agent)
#   - SKILLS_SOURCE_PATH   (optional; if set and exists, symlinks each
#                          subdir into ~/.claude/skills/)
#
# Usage (called from a host bootstrap):
#   SANDBOX_DIR=/path/to/sandbox bash agents/claude-code/install.sh

set -euo pipefail

: "${SANDBOX_DIR:?SANDBOX_DIR must point at the sandbox repo root}"
: "${AGENT_HOME:=/home/agent}"
: "${AGENT_USER:=agent}"

echo "[cc-install] Installing Claude Code CLI..."
sudo -u "$AGENT_USER" npm install -g @anthropic-ai/claude-code

echo "[cc-install] Setting up hooks, patterns, settings..."
sudo -u "$AGENT_USER" mkdir -p \
  "$AGENT_HOME/.claude/hooks" \
  "$AGENT_HOME/.claude/hooks/patterns" \
  "$AGENT_HOME/.claude/skills"

# Hooks
sudo cp "$SANDBOX_DIR/agents/claude-code/hooks/cred-guard.sh" \
        "$AGENT_HOME/.claude/hooks/cred-guard.sh"
sudo cp "$SANDBOX_DIR/agents/claude-code/hooks/redactor.sh" \
        "$AGENT_HOME/.claude/hooks/redactor.sh"
sudo chmod +x "$AGENT_HOME/.claude/hooks/"*.sh

# Patterns (shared with Pi's extensions)
sudo cp "$SANDBOX_DIR/shared/patterns/"*.json \
        "$AGENT_HOME/.claude/hooks/patterns/"

# Settings — expand $HOME to the agent's actual home
sudo cp "$SANDBOX_DIR/agents/claude-code/settings.json.template" \
        "$AGENT_HOME/.claude/settings.json"
sudo sed -i.bak "s|\$HOME|$AGENT_HOME|g" "$AGENT_HOME/.claude/settings.json"
sudo rm -f "$AGENT_HOME/.claude/settings.json.bak"

sudo chown -R "$AGENT_USER:$AGENT_USER" "$AGENT_HOME/.claude"

# with_creds helper in agent's .bashrc (spec §7.2 Option 2).
# Skills define with_creds as a no-op; the sandbox VM overrides it with
# a function that routes through `sudo /usr/local/bin/run`, which loads
# locked secrets and drops privs back to the agent user before exec.
echo "[cc-install] Adding with_creds to agent's .bashrc..."
BASHRC="$AGENT_HOME/.bashrc"
if ! sudo grep -q "^with_creds" "$BASHRC" 2>/dev/null; then
  sudo tee -a "$BASHRC" >/dev/null <<'EOF'

# Sandbox credential wrapper (see sandbox/docs/superpowers/specs §7.2).
# Skills call `with_creds <cmd>` to invoke privileged commands; on the
# sandbox VM this routes through the `run` wrapper to load locked
# secrets; on Mac `with_creds` is absent and skills default to a no-op.
with_creds() {
  if [ -x /usr/local/bin/run ]; then
    sudo /usr/local/bin/run "$@"
  else
    "$@"
  fi
}
export -f with_creds
EOF
  sudo chown "$AGENT_USER:$AGENT_USER" "$BASHRC"
fi

# Optional skill symlinks if the workspace configured a path.
if [ -n "${SKILLS_SOURCE_PATH:-}" ] && [ -d "$SKILLS_SOURCE_PATH" ]; then
  echo "[cc-install] Symlinking skills from $SKILLS_SOURCE_PATH..."
  for skill_dir in "$SKILLS_SOURCE_PATH"/*/; do
    [ -d "$skill_dir" ] || continue
    skill_name="$(basename "$skill_dir")"
    # Skip helper dirs like _common that start with underscore.
    case "$skill_name" in
      _*) continue;;
    esac
    sudo -u "$AGENT_USER" ln -sf "$skill_dir" \
      "$AGENT_HOME/.claude/skills/$skill_name"
  done
fi

echo "[cc-install] Done."
