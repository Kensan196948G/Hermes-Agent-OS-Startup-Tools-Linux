#!/usr/bin/env bats
# doctor.sh / prereq.sh — 診断の判定と evidence の誠実性
#
# 核心: doctor は「未確認」を PASS と偽らない。
#       実測が 0 件のときに「実測に基づく」と言わない。

setup() {
  load '../helper.bash'
}

@test "doctor: runs and reports PASS/WARN/FAIL/SKIP counters" {
  run run_iso doctor --quick
  assert_output_contains 'PASS='
  assert_output_contains 'WARN='
  assert_output_contains 'FAIL='
  assert_output_contains 'SKIP='
}

@test "doctor: always prints recommended_next_action" {
  run run_iso doctor --quick
  assert_output_contains 'recommended_next_action'
}

@test "doctor: missing hermes is reported as FAIL not PASS" {
  local tmp_home; tmp_home="$(mktemp -d)"
  mkdir -p "${tmp_home}/empty-path"
  run env HOME="$tmp_home" NO_COLOR=1 \
    PATH="${tmp_home}/empty-path:/usr/bin:/bin" \
    HERMES_BIN="${tmp_home}/__no_hermes__" OMH_BIN="${tmp_home}/__no_omh__" \
    "$PROJECT_ROOT/start.sh" doctor --quick
  rm -rf "$tmp_home"

  assert_output_contains 'hermes コマンドが無い'
}

@test "doctor: detects Linux environment" {
  run run_iso doctor --quick
  assert_output_contains 'Linux native'
}

@test "prereq: passes with bash/curl/git present" {
  run run_iso prereq
  [ "$status" -eq 0 ]
  assert_output_contains '前提検査を通過しました'
}

@test "prereq: does not treat installer-bundled tools as hard requirements" {
  run run_iso prereq
  [ "$status" -eq 0 ]
  # uv 等は任意であり、欠落しても失敗してはならない
  assert_output_contains '任意'
}

@test "evidence: rules text defines all four boundary classes" {
  run run_iso evidence rules
  [ "$status" -eq 0 ]
  assert_output_contains 'OBSERVED'
  assert_output_contains 'PREPARED'
  assert_output_contains 'PROPOSED'
  assert_output_contains 'NOT_OBSERVED'
}

@test "evidence: self-check never claims measurement with zero observations" {
  local tmp_home; tmp_home="$(mktemp -d)"
  mkdir -p "${tmp_home}/empty-path"
  # 隔離 HOME かつカタログが読める状態。hermes/omh は無い。
  run env HOME="$tmp_home" NO_COLOR=1 \
    PATH="${tmp_home}/empty-path:/usr/bin:/bin" \
    HERMES_BIN="${tmp_home}/__no_hermes__" OMH_BIN="${tmp_home}/__no_omh__" \
    "$PROJECT_ROOT/start.sh" evidence check
  rm -rf "$tmp_home"

  # 観測 0 件なら合格を主張してはならない
  if [[ "$output" != *'OBSERVED'* ]]; then
    fail "evidence check must report an OBSERVED count; got: $output"
  fi
  assert_output_not_contains 'OBSERVED 0 件・矛盾なし'
}

@test "evidence: write creates the rules file under HERMES_HOME" {
  local tmp_home; tmp_home="$(mktemp -d)"
  mkdir -p "${tmp_home}/empty-path"
  run env HOME="$tmp_home" NO_COLOR=1 \
    PATH="${tmp_home}/empty-path:/usr/bin:/bin" \
    HERMES_BIN="${tmp_home}/__no_hermes__" OMH_BIN="${tmp_home}/__no_omh__" \
    "$PROJECT_ROOT/start.sh" evidence write
  local rc="$status"
  [ -f "${tmp_home}/.hermes/EVIDENCE_RULES.md" ]
  rm -rf "$tmp_home"
  [ "$rc" -eq 0 ]
}

@test "doctor: reports OMH not setup when artifacts are absent" {
  local tmp_home; tmp_home="$(mktemp -d)"
  mkdir -p "${tmp_home}/empty-path"
  run env HOME="$tmp_home" NO_COLOR=1 \
    PATH="${tmp_home}/empty-path:/usr/bin:/bin" \
    HERMES_BIN="${tmp_home}/__no_hermes__" OMH_BIN="${tmp_home}/__no_omh__" \
    "$PROJECT_ROOT/start.sh" doctor --quick
  rm -rf "$tmp_home"
  assert_output_contains 'omh コマンドが無い'
}
