#!/bin/bash
# Install Claude Code for the 'agent' user. Idempotent.
#
# Expects:
#   - $SANDBOX_DIR env var points at the sandbox repo root
#   - agent user exists
#   - curl available (for the native installer)
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
# Install via the native installer into the agent's home dir so the agent
# user owns the binary and can auto-update without sudo.
sudo -u "$AGENT_USER" bash -c 'curl -fsSL https://claude.ai/install.sh | bash'

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

# User-level CLAUDE.md — auto-loaded on every session for the agent user.
# Documents the with_creds / sudo run pattern so bare claude sessions
# (outside any skill workflow) know how to use credentialed CLIs.
sudo cp "$SANDBOX_DIR/agents/claude-code/CLAUDE.md" \
        "$AGENT_HOME/.claude/CLAUDE.md"

sudo chown -R "$AGENT_USER:$AGENT_USER" "$AGENT_HOME/.claude"

# Install with_creds as a system binary (works in every shell context
# Claude can invoke — including non-interactive shells where ~/.bashrc
# is short-circuited by Ubuntu's standard "return if non-interactive"
# guard). See spec §7.2 Option 2.
echo "[cc-install] Installing with_creds binary..."
sudo install -m 755 "$SANDBOX_DIR/shared/scripts/with_creds" /usr/local/bin/with_creds

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
