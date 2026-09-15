#!/usr/bin/env bats

SCRIPT="$BATS_TEST_DIRNAME/../refresh-cursor-token"

@test "self-test: jwt expiry and env upsert" {
  run "$SCRIPT" --self-test
  [ "$status" -eq 0 ]
  [ "$output" = "self_test_ok" ]
}

@test "help mentions the exchange endpoint" {
  run "$SCRIPT" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"exchange_user_api_key"* ]]
}
