#!/usr/bin/env bats

load test_helper

@test "redactor replaces Anthropic API key" {
  output_with_key="Response: sk-ant-api03-ABCxyz123-fake"
  run bash "$HOOKS_DIR/redactor.sh" <<< "$(post_event "$output_with_key")"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "[REDACTED]" ]]
  [[ ! "$output" =~ "sk-ant-api03-ABCxyz123-fake" ]]
}

@test "redactor replaces AWS access key" {
  output_with_key="AWS_ACCESS_KEY_ID=AKIAIOSFODNN7EXAMPLE"
  run bash "$HOOKS_DIR/redactor.sh" <<< "$(post_event "$output_with_key")"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "[REDACTED]" ]]
  [[ ! "$output" =~ "AKIAIOSFODNN7EXAMPLE" ]]
}

@test "redactor replaces GitHub PAT" {
  output_with_pat="Token: ghp_abcdefghijklmnopqrstuvwxyz0123456789"
  run bash "$HOOKS_DIR/redactor.sh" <<< "$(post_event "$output_with_pat")"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "[REDACTED]" ]]
}

@test "redactor passes non-matching output through unchanged" {
  plain="Hello, world. Nothing sensitive here."
  run bash "$HOOKS_DIR/redactor.sh" <<< "$(post_event "$plain")"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Hello, world. Nothing sensitive here." ]]
}

@test "redactor replaces multiple matches in one output" {
  multi="Keys: sk-ant-ONE-xyz and AKIAIOSFODNN7EXAMPLE in one string"
  run bash "$HOOKS_DIR/redactor.sh" <<< "$(post_event "$multi")"
  [ "$status" -eq 0 ]
  match_count="$(grep -oc '\[REDACTED\]' <<< "$output" || true)"
  [ "$match_count" -ge 2 ]
}

@test "redactor errors loud if redactor.json missing" {
  CLAUDE_HOOKS_PATTERNS_DIR=/nonexistent run bash "$HOOKS_DIR/redactor.sh" <<< "$(post_event 'foo')"
  [ "$status" -ne 0 ]
  [[ "$output" =~ "redactor.json" ]]
}
