#!/usr/bin/env bats
# routing.sh / sessions.sh / yaml.sh / json.sh — 個別ユニット

setup() {
  load '../helper.bash'
  TEST_HOME="$(mktemp -d)"
}

teardown() {
  rm -rf "$TEST_HOME"
}

# ---------- routing ----------

@test "routing: status warns when model-chains.json is absent" {
  run env HOME="$TEST_HOME" NO_COLOR=1 "$PROJECT_ROOT/start.sh" routing status
  assert_output_contains 'model-chains.json がありません'
}

@test "routing: seed creates schema-valid file" {
  run env HOME="$TEST_HOME" NO_COLOR=1 "$PROJECT_ROOT/start.sh" routing seed
  [ "$status" -eq 0 ]
  assert_output_contains 'model-chains.json を作成しました'

  [ -f "${TEST_HOME}/.omh/routing/model-chains.json" ]
  run jq -r '.schema_version' "${TEST_HOME}/.omh/routing/model-chains.json"
  [ "$output" = "mixture_chain_overrides/v1" ]
}

@test "routing: seed creates empty categories (shipped defaults apply)" {
  env HOME="$TEST_HOME" NO_COLOR=1 "$PROJECT_ROOT/start.sh" routing seed >/dev/null 2>&1
  run jq -r '.categories | length' "${TEST_HOME}/.omh/routing/model-chains.json"
  [ "$output" = "0" ]
}

@test "routing: validate passes on seeded file" {
  env HOME="$TEST_HOME" NO_COLOR=1 "$PROJECT_ROOT/start.sh" routing seed >/dev/null 2>&1
  run env HOME="$TEST_HOME" NO_COLOR=1 "$PROJECT_ROOT/start.sh" routing validate
  [ "$status" -eq 0 ]
  assert_output_contains '有効な JSON'
  assert_output_contains 'mixture_chain_overrides/v1'
}

@test "routing: set writes a chain and backs up the previous file" {
  env HOME="$TEST_HOME" NO_COLOR=1 "$PROJECT_ROOT/start.sh" routing seed >/dev/null 2>&1
  run env HOME="$TEST_HOME" NO_COLOR=1 "$PROJECT_ROOT/start.sh" \
    routing set research cheap-a fast-b
  [ "$status" -eq 0 ]

  run jq -r '.categories.research | join(" -> ")' "${TEST_HOME}/.omh/routing/model-chains.json"
  [ "$output" = "cheap-a -> fast-b" ]

  # バックアップが取られていること (破壊しない設計の検証)
  run bash -c "ls ${TEST_HOME}/.omh/routing/model-chains.json.bak.* >/dev/null 2>&1"
  [ "$status" -eq 0 ]
}

@test "routing: validate fails on corrupt JSON" {
  mkdir -p "${TEST_HOME}/.omh/routing"
  echo '{ broken' > "${TEST_HOME}/.omh/routing/model-chains.json"
  run env HOME="$TEST_HOME" NO_COLOR=1 "$PROJECT_ROOT/start.sh" routing validate
  [ "$status" -ne 0 ]
  assert_output_contains '不正な JSON'
}

# ---------- sessions ----------

@test "sessions: status reports no sessions cleanly" {
  run run_iso sessions status
  [ "$status" -eq 0 ]
  assert_output_contains '実行中の'
}

@test "sessions: bg requires tmux and refuses without hermes installed" {
  mkdir -p "${TEST_HOME}/empty-path"
  run env HOME="$TEST_HOME" NO_COLOR=1 \
    PATH="${TEST_HOME}/empty-path:/usr/bin:/bin" \
    HERMES_BIN="${TEST_HOME}/__no_hermes__" OMH_BIN="${TEST_HOME}/__no_omh__" \
    "$PROJECT_ROOT/start.sh" bg testproj "$TEST_HOME"
  [ "$status" -ne 0 ]
  assert_output_contains '未導入'
}

# ---------- yaml ----------

@test "yaml: yaml_get reads a top-level key" {
  local f="${TEST_HOME}/c.yaml"
  printf 'model: gpt-4\nother: x\n' > "$f"
  run bash -c "source '${PROJECT_ROOT}/lib/json.sh'; source '${PROJECT_ROOT}/lib/yaml.sh'; yaml_get '$f' model"
  [ "$output" = "gpt-4" ]
}

@test "yaml: yaml_get reads a nested key" {
  local f="${TEST_HOME}/c.yaml"
  printf 'skills:\n  external_dirs: /home/u/.omh/skills\n' > "$f"
  run bash -c "source '${PROJECT_ROOT}/lib/json.sh'; source '${PROJECT_ROOT}/lib/yaml.sh'; yaml_get '$f' skills.external_dirs"
  [ "$output" = "/home/u/.omh/skills" ]
}

@test "yaml: yaml_get strips surrounding quotes" {
  local f="${TEST_HOME}/c.yaml"
  printf 'model: "quoted-value"\n' > "$f"
  run bash -c "source '${PROJECT_ROOT}/lib/json.sh'; source '${PROJECT_ROOT}/lib/yaml.sh'; yaml_get '$f' model"
  [ "$output" = "quoted-value" ]
}

@test "yaml: yaml_get returns default for missing key" {
  local f="${TEST_HOME}/c.yaml"
  printf 'model: a\n' > "$f"
  run bash -c "source '${PROJECT_ROOT}/lib/json.sh'; source '${PROJECT_ROOT}/lib/yaml.sh'; yaml_get '$f' nope FALLBACK"
  [ "$output" = "FALLBACK" ]
}

# 回帰テスト: 複数行配列を「キーが無い」と誤って既定値で返すと、
# 呼び出し側が黙って間違った値を使う。番兵値で区別する。
@test "yaml: multi-line array returns sentinel, not the default" {
  local f="${TEST_HOME}/arr.yaml"
  cat > "$f" <<'YAML'
skills:
  external_dirs:
    - /home/u/.omh/skills
  creation_nudge_interval: 15
YAML

  run bash -c "source '${PROJECT_ROOT}/lib/json.sh'; source '${PROJECT_ROOT}/lib/yaml.sh'; yaml_get '$f' skills.external_dirs"
  [ "$output" = "__YAML_MULTILINE__" ]
}

@test "yaml: yaml_list_get reads the multi-line array items" {
  local f="${TEST_HOME}/arr2.yaml"
  cat > "$f" <<'YAML'
skills:
  external_dirs:
    - /home/u/.omh/skills
    - /other/skills
YAML

  run bash -c "source '${PROJECT_ROOT}/lib/json.sh'; source '${PROJECT_ROOT}/lib/yaml.sh'; yaml_list_get '$f' skills.external_dirs"
  [ "$status" -eq 0 ]
  assert_output_contains '/home/u/.omh/skills'
  assert_output_contains '/other/skills'
}

@test "yaml: yaml_list_get stops at the next key" {
  local f="${TEST_HOME}/arr3.yaml"
  cat > "$f" <<'YAML'
skills:
  external_dirs:
    - /only/this
  creation_nudge_interval: 15
YAML

  run bash -c "source '${PROJECT_ROOT}/lib/json.sh'; source '${PROJECT_ROOT}/lib/yaml.sh'; yaml_list_get '$f' skills.external_dirs"
  assert_output_contains '/only/this'
  assert_output_not_contains 'creation_nudge_interval'
  assert_output_not_contains '15'
}

# ---------- json ----------

@test "json: json_valid accepts valid and rejects invalid" {
  local good="${TEST_HOME}/good.json" bad="${TEST_HOME}/bad.json"
  echo '{"a":1}' > "$good"
  echo '{oops' > "$bad"

  run bash -c "source '${PROJECT_ROOT}/lib/common.sh'; source '${PROJECT_ROOT}/lib/json.sh'; json_valid '$good'"
  [ "$status" -eq 0 ]

  run bash -c "source '${PROJECT_ROOT}/lib/common.sh'; source '${PROJECT_ROOT}/lib/json.sh'; json_valid '$bad'"
  [ "$status" -ne 0 ]
}

@test "json: json_get_bool normalizes truthy values" {
  local f="${TEST_HOME}/b.json"
  echo '{"on":true,"off":false}' > "$f"
  run bash -c "source '${PROJECT_ROOT}/lib/common.sh'; source '${PROJECT_ROOT}/lib/json.sh'; json_get_bool '$f' .on"
  [ "$output" = "true" ]
  run bash -c "source '${PROJECT_ROOT}/lib/common.sh'; source '${PROJECT_ROOT}/lib/json.sh'; json_get_bool '$f' .off false"
  [ "$output" = "false" ]
}

# ---------- dry-run ----------

@test "dry-run: HERMESOS_DRY_RUN prevents install execution" {
  local tmp_home; tmp_home="$(mktemp -d)"
  mkdir -p "${tmp_home}/empty-path"
  run env HOME="$tmp_home" NO_COLOR=1 HERMESOS_DRY_RUN=1 \
    PATH="${tmp_home}/empty-path:/usr/bin:/bin" \
    HERMES_BIN="${tmp_home}/__no_hermes__" OMH_BIN="${tmp_home}/__no_omh__" \
    "$PROJECT_ROOT/start.sh" install hermes
  rm -rf "$tmp_home"

  # dry-run では installer を流さない。事前チェックのみで停止する。
  assert_output_not_contains 'installer が完了しました'
  assert_output_not_contains 'installer の実行が完了しました'
  assert_output_contains '未実行です'
}

@test "dry-run: omh install does not claim success (evidence boundary)" {
  local tmp_home; tmp_home="$(mktemp -d)"
  mkdir -p "${tmp_home}/empty-path"
  run env HOME="$tmp_home" NO_COLOR=1 HERMESOS_DRY_RUN=1 \
    PATH="${tmp_home}/empty-path:/usr/bin:/bin" \
    HERMES_BIN="${tmp_home}/__no_hermes__" OMH_BIN="${tmp_home}/__no_omh__" \
    "$PROJECT_ROOT/start.sh" install omh npm
  rm -rf "$tmp_home"

  [ "$status" -eq 0 ]
  # 何も導入していないのに「完了」と言ってはならない
  assert_output_not_contains '導入が完了しました'
  assert_output_not_contains '導入を確認しました'
  assert_output_contains '未実行です'
}
