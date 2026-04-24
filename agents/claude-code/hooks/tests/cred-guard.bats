#!/usr/bin/env bats

load test_helper

@test "cred-guard blocks Bash: cat .env" {
  run bash "$HOOKS_DIR/cred-guard.sh" <<< "$(bash_event 'cat .env')"
  [ "$status" -eq 2 ]
  [[ "$output" =~ "blocked" ]] || [[ "$output" =~ "credential" ]]
}

@test "cred-guard blocks Bash: printenv" {
  run bash "$HOOKS_DIR/cred-guard.sh" <<< "$(bash_event 'printenv')"
  [ "$status" -eq 2 ]
}

@test "cred-guard blocks Bash: sudo cat /etc/devbox/secrets" {
  run bash "$HOOKS_DIR/cred-guard.sh" <<< "$(bash_event 'sudo cat /etc/devbox/secrets')"
  [ "$status" -eq 2 ]
}

@test "cred-guard blocks Bash: python -c os.environ" {
  run bash "$HOOKS_DIR/cred-guard.sh" <<< "$(bash_event 'python -c "import os; print(os.environ)"')"
  [ "$status" -eq 2 ]
}

@test "cred-guard allows Bash: sudo run psql" {
  run bash "$HOOKS_DIR/cred-guard.sh" <<< "$(bash_event 'sudo run psql "$DB_URL" -c "SELECT 1"')"
  [ "$status" -eq 0 ]
}

@test "cred-guard allows Bash: plain ls" {
  run bash "$HOOKS_DIR/cred-guard.sh" <<< "$(bash_event 'ls -la')"
  [ "$status" -eq 0 ]
}

@test "cred-guard blocks Read: .env file" {
  run bash "$HOOKS_DIR/cred-guard.sh" <<< "$(read_event '/workspace/core/backend/.env')"
  [ "$status" -eq 2 ]
}

@test "cred-guard blocks Read: /etc/devbox/secrets" {
  run bash "$HOOKS_DIR/cred-guard.sh" <<< "$(read_event '/etc/devbox/secrets')"
  [ "$status" -eq 2 ]
}

@test "cred-guard allows Read: regular source file" {
  run bash "$HOOKS_DIR/cred-guard.sh" <<< "$(read_event '/workspace/core/backend/src/models.py')"
  [ "$status" -eq 0 ]
}

@test "cred-guard returns clear reason on stderr when blocking" {
  run bash "$HOOKS_DIR/cred-guard.sh" <<< "$(bash_event 'cat .env')"
  [ "$status" -eq 2 ]
  [[ "$output" =~ "pattern" ]]
}

@test "cred-guard errors loud if cred-guard.json missing" {
  CLAUDE_HOOKS_PATTERNS_DIR=/nonexistent run bash "$HOOKS_DIR/cred-guard.sh" <<< "$(bash_event 'ls')"
  [ "$status" -ne 0 ]
  [[ "$output" =~ "cred-guard.json" ]]
}
