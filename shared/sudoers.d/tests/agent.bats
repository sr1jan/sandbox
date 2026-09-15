#!/usr/bin/env bats

# Pins shared/sudoers.d/agent: run-only escalation + env_keep so sudo run
# (the /usr/local/bin/pi wrapper) still forwards Herdr pane identity.

SUDOERS="$BATS_TEST_DIRNAME/../agent"

@test "agent may sudo run only — no NOPASSWD shells" {
  grep -E '^agent ALL=\(root\) NOPASSWD: /usr/local/bin/run \*$' "$SUDOERS"
  ! grep -E 'NOPASSWD:.*(/bin/bash|/bin/sh|/usr/bin/bash)' "$SUDOERS"
}

@test "env_keep preserves tmux identity" {
  grep -E '^Defaults env_keep \+= ".*\bTMUX\b' "$SUDOERS"
  grep -E '^Defaults env_keep \+= ".*\bTMUX_PANE\b' "$SUDOERS"
}

@test "env_keep preserves herdr pane identity for sudo run pi" {
  grep -E '^Defaults env_keep \+= "' "$SUDOERS" | grep -E '\bHERDR_ENV\b'
  grep -E '^Defaults env_keep \+= "' "$SUDOERS" | grep -E '\bHERDR_PANE_ID\b'
  grep -E '^Defaults env_keep \+= "' "$SUDOERS" | grep -E '\bHERDR_SESSION\b'
  grep -E '^Defaults env_keep \+= "' "$SUDOERS" | grep -E '\bHERDR_SOCKET_PATH\b'
  grep -E '^Defaults env_keep \+= "' "$SUDOERS" | grep -E '\bHERDR_TAB_ID\b'
  grep -E '^Defaults env_keep \+= "' "$SUDOERS" | grep -E '\bHERDR_WORKSPACE_ID\b'
}
