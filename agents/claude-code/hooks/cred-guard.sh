#!/bin/bash
# Claude Code PreToolUse hook: blocks tool calls that would expose credentials.
#
# Input: JSON payload on stdin, e.g.:
#   {"tool":"Bash","input":{"command":"<string>"}}
#   {"tool":"Read","input":{"file_path":"<string>"}}
#   {"tool":"Edit","input":{"file_path":"<string>","old_string":"...","new_string":"..."}}
#   {"tool":"Write","input":{"file_path":"<string>","content":"..."}}
#
# Exit codes:
#   0 = allow (tool call proceeds)
#   2 = block (Claude sees the block reason in its tool result)
#   3 = hard error (patterns file missing — surfaced to user)
#
# Patterns are loaded from $CLAUDE_HOOKS_PATTERNS_DIR/cred-guard.json
# (default: $HOME/.claude/hooks/patterns/). The same JSON is also
# consumed by Pi's cred-guard TypeScript extension.

set -euo pipefail

PATTERNS_DIR="${CLAUDE_HOOKS_PATTERNS_DIR:-$HOME/.claude/hooks/patterns}"
PATTERNS_FILE="$PATTERNS_DIR/cred-guard.json"

if [ ! -f "$PATTERNS_FILE" ]; then
  echo "cred-guard.json not found at $PATTERNS_FILE" >&2
  exit 3
fi

event_json="$(cat)"
tool="$(jq -r '.tool // empty' <<< "$event_json")"

case "$tool" in
  Bash)
    command="$(jq -r '.input.command // empty' <<< "$event_json")"
    if [ -z "$command" ]; then
      exit 0
    fi
    while IFS= read -r p; do
      [ -z "$p" ] && continue
      if grep -qE "$p" <<< "$command"; then
        echo "blocked: bash command matches credential-exposure pattern: $p" >&2
        exit 2
      fi
    done < <(jq -r '.bash_patterns[]' "$PATTERNS_FILE")
    exit 0
    ;;
  Read|Edit|Write)
    path="$(jq -r '.input.file_path // empty' <<< "$event_json")"
    if [ -z "$path" ]; then
      exit 0
    fi
    while IFS= read -r p; do
      [ -z "$p" ] && continue
      if grep -qiE "$p" <<< "$path"; then
        echo "blocked: file path matches credential pattern: $p" >&2
        exit 2
      fi
    done < <(jq -r '.file_patterns[]' "$PATTERNS_FILE")
    exit 0
    ;;
  *)
    # Unknown/other tool — allow through.
    exit 0
    ;;
esac
