#!/bin/bash
# Shared test helper for Claude Code hook bats tests.
# Provides paths, temp dirs, and a mock patterns dir pointing at fixtures.

setup() {
  TEST_DIR="$BATS_TEST_DIRNAME"
  HOOKS_DIR="$(cd "$TEST_DIR/.." && pwd)"
  FIXTURES_DIR="$TEST_DIR/fixtures"

  # Claude Code passes hook input via stdin as JSON. Tests simulate this
  # by piping a crafted JSON payload into the hook. The hook reads its
  # pattern JSON from $CLAUDE_HOOKS_PATTERNS_DIR, so we point it at the
  # fixtures dir for isolation from any real patterns on the machine.
  export CLAUDE_HOOKS_PATTERNS_DIR="$FIXTURES_DIR"
}

teardown() { :; }

# Helper: emit a PreToolUse event payload for the Bash tool.
# Schema matches Claude Code's actual hook input: tool_name + tool_input.
bash_event() {
  local cmd="$1"
  printf '{"tool_name":"Bash","tool_input":{"command":%s}}' \
    "$(printf '%s' "$cmd" | jq -Rs .)"
}

# Helper: emit a PreToolUse event payload for Read/Edit/Write (all use file_path).
read_event() {
  local path="$1"
  printf '{"tool_name":"Read","tool_input":{"file_path":%s}}' \
    "$(printf '%s' "$path" | jq -Rs .)"
}

# Helper: emit a PostToolUse event payload with tool_result stdout/stderr.
# (Kept on the legacy schema for now — the redactor hook is unfixed; see
# Layer 4 audit. Update alongside the redactor rewrite.)
post_event() {
  local stdout="$1"
  printf '{"tool":"Bash","tool_result":{"stdout":%s,"stderr":""}}' \
    "$(printf '%s' "$stdout" | jq -Rs .)"
}
