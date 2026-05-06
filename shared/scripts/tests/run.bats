#!/usr/bin/env bats

# Tests for the cwd → REL mapping in shared/scripts/run.
#
# These exercise the bash parameter expansions inline rather than invoking
# the full script (which would need sudo + gosu + a fixture filesystem under
# /etc/devbox/locked). The "drift detector" test below pins the script's
# source against the same expansions so this file fails loudly if `run`
# changes its mapping logic without corresponding test updates.

RUN_SCRIPT="$BATS_TEST_DIRNAME/../run"

# Mirror of the REL computation in `run`. Keep in sync with the script.
map_rel() {
  local cwd="$1"
  local rel="${cwd#/workspace/}"
  rel="${rel%%/.worktrees/*}"
  printf '%s' "$rel"
}

@test "run script contains worktree-stripping expansion" {
  # Guards against silent drift between this test file and the script.
  grep -qF 'REL="${REL%%/.worktrees/*}"' "$RUN_SCRIPT"
}

@test "rel mapping: plain project cwd" {
  result="$(map_rel /workspace/core/backend)"
  [ "$result" = "core/backend" ]
}

@test "rel mapping: subdir under project unchanged" {
  result="$(map_rel /workspace/core/backend/some/sub)"
  [ "$result" = "core/backend/some/sub" ]
}

@test "rel mapping: worktree collapses to base project" {
  result="$(map_rel /workspace/core/backend/.worktrees/feat/video-project-editor)"
  [ "$result" = "core/backend" ]
}

@test "rel mapping: worktree subdir collapses to base project" {
  result="$(map_rel /workspace/core/backend/.worktrees/feat/video-project-editor/tests/unit)"
  [ "$result" = "core/backend" ]
}

@test "rel mapping: project name containing 'worktrees' substring is unaffected" {
  # Pattern requires the literal "/.worktrees/" segment, so a hyphenated
  # project name shouldn't trigger the strip.
  result="$(map_rel /workspace/core/backend-worktrees-info)"
  [ "$result" = "core/backend-worktrees-info" ]
}

@test "rel mapping: cwd outside /workspace/ unchanged" {
  result="$(map_rel /tmp/foo/bar)"
  [ "$result" = "/tmp/foo/bar" ]
}
