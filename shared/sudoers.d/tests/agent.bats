#!/usr/bin/env bats

# Pins shared/sudoers.d/agent env_keep so sudo run (the /usr/local/bin/pi
# wrapper) still forwards Herdr pane identity to the real pi process.

SUDOERS="$BATS_TEST_DIRNAME/../agent"

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
