#!/usr/bin/env bats
# routing readiness — 上流 'omh coding model-routing status --json' の要約
#
# 上流の生出力は 100KB 超になり得る (discovered 668 件)。
# 本ツールは判断に必要な要点だけを抽出する。
# 上流の主張境界 (discovered は実行証明ではない) を要約で消さないことを検証する。

setup() {
  load '../helper.bash'
  TEST_HOME="$(mktemp -d)"
  STUB_DIR="${TEST_HOME}/bin"
  mkdir -p "$STUB_DIR"
}

teardown() {
  rm -rf "$TEST_HOME"
}

# stub_omh_routing <confirmed_json_array>
stub_omh_routing() {
  local confirmed="${1:-[]}"
  cat > "${STUB_DIR}/omh" <<STUB
#!/usr/bin/env bash
if [[ "\$1" == "--version" ]]; then echo "omh 9.9.9-stub"; exit 0; fi
if [[ "\$1" == "coding" && "\$2" == "model-routing" && "\$3" == "status" ]]; then
  cat <<'JSON'
{
  "schema_version": "model_routing_status/v1",
  "status": "needs_confirmation",
  "next_action": "Confirm locally active models.",
  "claim_boundary": "Discovered is not execution proof.",
  "models": {
    "confirmed": ${confirmed},
    "discovered_only": [{"model_id":"m-a"},{"model_id":"m-a"},{"model_id":"m-b"}],
    "discovery_truncated": true,
    "source_statuses": {"claude-code":"truncated","hermes":"unobserved"}
  },
  "hermes": {"status":"aliases_unset","recommendation":{"recommended_head":"kimi-k3"}},
  "maestro": {"missing_heads":["kimi-k3","glm-5.3"]},
  "owner_learning": {"status":"missing","path":"/home/kensan/.omh/routing/owner-preference.json"}
}
JSON
  exit 0
fi
echo "stub omh: \$*"; exit 0
STUB
  chmod +x "${STUB_DIR}/omh"
}

run_readiness() {
  run env HOME="$TEST_HOME" NO_COLOR=1 \
    PATH="${STUB_DIR}:/usr/bin:/bin" \
    HERMES_BIN="${TEST_HOME}/__no_hermes__" \
    OMH_BIN="${STUB_DIR}/omh" \
    "$PROJECT_ROOT/start.sh" "$@"
}

@test "routing readiness: reports confirmed 0 as unconfirmed (exit 2)" {
  stub_omh_routing '[]'
  run_readiness routing readiness
  [ "$status" -eq 2 ]
  assert_output_contains 'confirmed (実行に使える) 0'
  assert_output_contains 'confirmed が 0 件です'
  assert_output_contains 'ルーティングは未確定'
}

@test "routing readiness: reports confirmed count when present (exit 0)" {
  stub_omh_routing '[{"model_id":"x"},{"model_id":"y"}]'
  run_readiness routing readiness
  [ "$status" -eq 0 ]
  assert_output_contains 'confirmed 2 件'
}

@test "routing readiness: deduplicates discovered model names" {
  stub_omh_routing '[]'
  run_readiness routing readiness
  assert_output_contains 'discovered ユニーク名'
  # m-a が2回, m-b が1回 → ユニーク 2
  assert_output_contains '2'
}

@test "routing readiness: surfaces truncated discovery honestly" {
  stub_omh_routing '[]'
  run_readiness routing readiness
  assert_output_contains 'truncated'
}

@test "routing readiness: preserves the upstream claim boundary" {
  stub_omh_routing '[]'
  run_readiness routing readiness
  # 要約で境界表明を消してはならない
  assert_output_contains 'Discovered is not execution proof'
}

@test "routing readiness: shows missing maestro heads" {
  stub_omh_routing '[]'
  run_readiness routing readiness
  assert_output_contains 'kimi-k3'
  assert_output_contains 'glm-5.3'
}

@test "routing readiness: shows hermes aliases_unset" {
  stub_omh_routing '[]'
  run_readiness routing readiness
  assert_output_contains 'aliases_unset'
}

@test "routing readiness: does not dump the full raw JSON" {
  stub_omh_routing '[]'
  run_readiness routing readiness
  # 生の JSON 構造がそのまま出てはいけない (要点のみ)
  assert_output_not_contains 'schema_version'
  assert_output_not_contains '"model_id"'
}

@test "doctor: surfaces routing not confirmed as a warning" {
  stub_omh_routing '[]'
  run_readiness doctor --quick
  assert_output_contains 'ルーティング未確定'
  assert_output_contains 'モデルルーティング準備度'
}

@test "routing readiness: handles missing/failed upstream gracefully" {
  cat > "${STUB_DIR}/omh" <<'STUB'
#!/usr/bin/env bash
if [[ "$1" == "--version" ]]; then echo "omh 9.9.9-stub"; exit 0; fi
exit 3
STUB
  chmod +x "${STUB_DIR}/omh"

  run_readiness routing readiness
  # 落ちずに、取得できないことを明示する
  assert_output_contains '取得できません'
}
