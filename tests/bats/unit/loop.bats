#!/usr/bin/env bats
# loop.sh — Loop Engineering のガードレール検証
#
# 最重要の規約: 検証 (verification) が空のイテレーションは記録できない。
# 「たぶん直った」を反復として数えないための防壁。

setup() {
  load '../helper.bash'
  TEST_HOME="$(mktemp -d)"
  export HERMESOS_LOOP_DIR="${TEST_HOME}/loops"
}

teardown() {
  rm -rf "$TEST_HOME"
}

@test "loop: create then show reports iteration 0 and open status" {
  run env HOME="$TEST_HOME" HERMESOS_LOOP_DIR="$HERMESOS_LOOP_DIR" NO_COLOR=1 \
    "$PROJECT_ROOT/start.sh" loop new "Test Loop" "verify objective"
  [ "$status" -eq 0 ]
  assert_output_contains 'ループを作成しました'

  run env HOME="$TEST_HOME" HERMESOS_LOOP_DIR="$HERMESOS_LOOP_DIR" NO_COLOR=1 \
    "$PROJECT_ROOT/start.sh" loop show test-loop
  [ "$status" -eq 0 ]
  assert_output_contains 'status     : open'
  assert_output_contains 'iteration  : 0 / 10'
}

@test "loop: iterate WITHOUT verification is rejected (guardrail)" {
  env HOME="$TEST_HOME" HERMESOS_LOOP_DIR="$HERMESOS_LOOP_DIR" NO_COLOR=1 \
    "$PROJECT_ROOT/start.sh" loop new "Guard" "obj" >/dev/null 2>&1

  run env HOME="$TEST_HOME" HERMESOS_LOOP_DIR="$HERMESOS_LOOP_DIR" NO_COLOR=1 \
    "$PROJECT_ROOT/start.sh" loop iterate guard "hyp" "act" "" "decide"

  [ "$status" -ne 0 ]
  assert_output_contains 'verification が空です'
  assert_output_contains '検証なき反復は記録できません'
}

@test "loop: iterate with verification succeeds and increments" {
  env HOME="$TEST_HOME" HERMESOS_LOOP_DIR="$HERMESOS_LOOP_DIR" NO_COLOR=1 \
    "$PROJECT_ROOT/start.sh" loop new "Ok" "obj" >/dev/null 2>&1

  run env HOME="$TEST_HOME" HERMESOS_LOOP_DIR="$HERMESOS_LOOP_DIR" NO_COLOR=1 \
    "$PROJECT_ROOT/start.sh" loop iterate ok "hyp" "act" "pytest -q -> 3 passed" "続行"
  [ "$status" -eq 0 ]
  assert_output_contains 'イテレーション 1 を記録しました'

  run env HOME="$TEST_HOME" HERMESOS_LOOP_DIR="$HERMESOS_LOOP_DIR" NO_COLOR=1 \
    "$PROJECT_ROOT/start.sh" loop show ok
  assert_output_contains 'pytest -q -> 3 passed'
  assert_output_contains 'hypothesis  : hyp'
}

@test "loop: whitespace-only verification is also rejected" {
  env HOME="$TEST_HOME" HERMESOS_LOOP_DIR="$HERMESOS_LOOP_DIR" NO_COLOR=1 \
    "$PROJECT_ROOT/start.sh" loop new "Ws" "obj" >/dev/null 2>&1

  run env HOME="$TEST_HOME" HERMESOS_LOOP_DIR="$HERMESOS_LOOP_DIR" NO_COLOR=1 \
    "$PROJECT_ROOT/start.sh" loop iterate ws "hyp" "act" "   " "decide"

  [ "$status" -ne 0 ]
  assert_output_contains 'verification が空です'
}

@test "loop: iterate on missing loop fails" {
  run env HOME="$TEST_HOME" HERMESOS_LOOP_DIR="$HERMESOS_LOOP_DIR" NO_COLOR=1 \
    "$PROJECT_ROOT/start.sh" loop iterate does-not-exist "h" "a" "v" "d"
  [ "$status" -ne 0 ]
  assert_output_contains 'ループがありません'
}

@test "loop: list shows created loops" {
  env HOME="$TEST_HOME" HERMESOS_LOOP_DIR="$HERMESOS_LOOP_DIR" NO_COLOR=1 \
    "$PROJECT_ROOT/start.sh" loop new "Alpha" "first" >/dev/null 2>&1
  env HOME="$TEST_HOME" HERMESOS_LOOP_DIR="$HERMESOS_LOOP_DIR" NO_COLOR=1 \
    "$PROJECT_ROOT/start.sh" loop new "Beta" "second" >/dev/null 2>&1

  run env HOME="$TEST_HOME" HERMESOS_LOOP_DIR="$HERMESOS_LOOP_DIR" NO_COLOR=1 \
    "$PROJECT_ROOT/start.sh" loop list
  [ "$status" -eq 0 ]
  assert_output_contains 'alpha'
  assert_output_contains 'beta'
}

@test "loop: guidance documents the four steps" {
  run run_iso loop guidance
  [ "$status" -eq 0 ]
  assert_output_contains 'Hypothesis'
  assert_output_contains 'Verification'
  assert_output_contains 'Decision'
}
