#!/bin/bash
# Claude Code PostToolUse hook: scrubs credential-shaped strings from tool output
# before it reaches Claude's context.
#
# Input: JSON payload on stdin with the tool result, e.g.:
#   {"tool":"Bash","tool_result":{"stdout":"...","stderr":"..."}}
#
# Output: same JSON with stdout/stderr scrubbed (matches replaced with the
# replacement string from redactor.json — default "[REDACTED]").
#
# Exit 0 = success; non-zero = error (patterns missing / invalid JSON).

set -euo pipefail

PATTERNS_DIR="${CLAUDE_HOOKS_PATTERNS_DIR:-$HOME/.claude/hooks/patterns}"
PATTERNS_FILE="$PATTERNS_DIR/redactor.json"

if [ ! -f "$PATTERNS_FILE" ]; then
  echo "redactor.json not found at $PATTERNS_FILE" >&2
  exit 3
fi

event_json="$(cat)"
replacement="$(jq -r '.replacement // "[REDACTED]"' "$PATTERNS_FILE")"

# Build sed -E args from patterns. Translate JS regex shorthand (\s, \S) to
# POSIX ERE so BSD sed on macOS and GNU sed on Linux both accept the patterns.
sed_args=()
has_patterns=0
while IFS= read -r pattern; do
  [ -z "$pattern" ] && continue
  has_patterns=1
  posix="$pattern"
  posix="${posix//\\s/[[:space:]]}"
  posix="${posix//\\S/[^[:space:]]}"
  sed_args+=("-e" "s#${posix}#${replacement}#g")
done < <(jq -r '.patterns[]' "$PATTERNS_FILE")

# Scrub stdout/stderr separately. If no patterns, pass through unchanged.
original_stdout="$(jq -r '.tool_result.stdout // ""' <<< "$event_json")"
original_stderr="$(jq -r '.tool_result.stderr // ""' <<< "$event_json")"

if [ "$has_patterns" -eq 1 ]; then
  scrubbed_stdout="$(printf '%s' "$original_stdout" | sed -E "${sed_args[@]}")"
  scrubbed_stderr="$(printf '%s' "$original_stderr" | sed -E "${sed_args[@]}")"
else
  scrubbed_stdout="$original_stdout"
  scrubbed_stderr="$original_stderr"
fi

jq -c \
  --arg stdout "$scrubbed_stdout" \
  --arg stderr "$scrubbed_stderr" \
  '.tool_result.stdout = $stdout | .tool_result.stderr = $stderr' \
  <<< "$event_json"
