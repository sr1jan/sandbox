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

# Hooks. Explicit paths, no glob: the caller (ubuntu) cannot traverse the
# 750 agent home, so "$AGENT_HOME/.claude/hooks/"*.sh would stay literal.
for hook in cred-guard.sh redactor.sh; do
  sudo install -m 755 -o "$AGENT_USER" -g "$AGENT_USER" \
    "$SANDBOX_DIR/agents/claude-code/hooks/$hook" "$AGENT_HOME/.claude/hooks/$hook"
done

# Patterns (shared with Pi's extensions)
sudo cp "$SANDBOX_DIR/shared/patterns/"*.json \
        "$AGENT_HOME/.claude/hooks/patterns/"

# Settings: render the template ($HOME -> agent home) and deep-merge it over
# the existing settings.json. Template keys (hooks, permissions, env) win on
# every run; keys Claude Code writes at runtime (model, plugins, theme,
# statusLine, ...) survive re-installs. Missing or non-object file -> template.
settings="$AGENT_HOME/.claude/settings.json"
rendered="$(sudo sed "s|\$HOME|$AGENT_HOME|g" "$SANDBOX_DIR/agents/claude-code/settings.json.template")"
if sudo test -f "$settings" && sudo jq -e 'type == "object"' "$settings" >/dev/null 2>&1; then
  merged="$(sudo jq --argjson tpl "$rendered" '. * $tpl' "$settings")"
else
  merged="$rendered"
fi
printf '%s\n' "$merged" | sudo tee "$settings" >/dev/null

# User-level CLAUDE.md — auto-loaded on every session for the agent user.
# Documents the with_creds / sudo run pattern so bare claude sessions
# (outside any skill workflow) know how to use credentialed CLIs, and the
# operator's writing rules for chat replies (ASD-STE100 based).
sudo cp "$SANDBOX_DIR/agents/claude-code/CLAUDE.md" \
        "$AGENT_HOME/.claude/CLAUDE.md"

sudo chown -R "$AGENT_USER:$AGENT_USER" "$AGENT_HOME/.claude"

# Install with_creds as a system binary (works in every shell context
# Claude can invoke — including non-interactive shells where ~/.bashrc
# is short-circuited by Ubuntu's standard "return if non-interactive"
# guard). See spec §7.2 Option 2.
echo "[cc-install] Installing with_creds binary..."
sudo install -m 755 "$SANDBOX_DIR/shared/scripts/with_creds" /usr/local/bin/with_creds

# Bundled skills shipped with this repo (agents/claude-code/skills/*).
BUNDLED_SKILLS="$SANDBOX_DIR/agents/claude-code/skills"
if [ -d "$BUNDLED_SKILLS" ]; then
  echo "[cc-install] Copying bundled skills..."
  for skill_dir in "$BUNDLED_SKILLS"/*/; do
    [ -d "$skill_dir" ] || continue
    skill_name="$(basename "$skill_dir")"
    sudo cp -r "$skill_dir" "$AGENT_HOME/.claude/skills/$skill_name"
    sudo chown -R "$AGENT_USER:$AGENT_USER" "$AGENT_HOME/.claude/skills/$skill_name"
  done
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
