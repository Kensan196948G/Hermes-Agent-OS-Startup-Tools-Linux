#!/usr/bin/env bats
# config-loader.sh — パス展開と既定値の検証
#
# 回帰テストの対象:
#   JSON から読んだ "~/.hermes" が $HOME/.hermes に展開されること。
#   過去に $HOME/~/.hermes になる不具合があった。

setup() {
  load '../helper.bash'
}

@test "config: tilde in hermes_home expands to \$HOME (not \$HOME/~)" {
  run run_iso config
  [ "$status" -eq 0 ]

  # 実 HOME が混ざっていないこと = 隔離 HOME で解決されている
  assert_output_not_contains '/~/.hermes'
  assert_output_not_contains '/~/.omh'
}

@test "config: 実効値セクションが表示される" {
  run run_iso config
  [ "$status" -eq 0 ]
  assert_output_contains 'HERMES_HOME'
  assert_output_contains 'OMH_HOME'
  assert_output_contains '設定の実効値'
}

@test "config: HERMES_HOME 環境変数が config.json より優先される" {
  local tmp_home; tmp_home="$(mktemp -d)"
  local custom="${tmp_home}/custom-hermes"

  run env HOME="$tmp_home" NO_COLOR=1 HERMES_HOME="$custom" \
    "$PROJECT_ROOT/start.sh" config
  rm -rf "$tmp_home"

  [ "$status" -eq 0 ]
  assert_output_contains "$custom"
}

@test "config: 壊れた config.json でも既定値で動作する" {
  local tmp_home; tmp_home="$(mktemp -d)"

  # 共有ファイル (実プロジェクトの config.json) を書き換えない。
  # HERMESOS_CONFIG_FILE で隔離した壊れたファイルを指す。
  local bad="${tmp_home}/broken.json"
  echo '{ this is not json' > "$bad"

  run env HOME="$tmp_home" NO_COLOR=1 HERMESOS_CONFIG_FILE="$bad" \
    "$PROJECT_ROOT/start.sh" config
  rm -rf "$tmp_home"

  [ "$status" -eq 0 ]
  assert_output_contains 'HERMES_HOME'
}

@test "config: 存在しない config.json でも既定値で動作する" {
  local tmp_home; tmp_home="$(mktemp -d)"

  run env HOME="$tmp_home" NO_COLOR=1 \
    HERMESOS_CONFIG_FILE="${tmp_home}/does-not-exist.json" \
    "$PROJECT_ROOT/start.sh" config
  rm -rf "$tmp_home"

  [ "$status" -eq 0 ]
  assert_output_contains 'HERMES_HOME'
}
