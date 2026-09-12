#!/usr/bin/env bats
# skills-catalog.sh — カタログ件数とデータ源の検証
#
# 出荷時スナップショットは OMH リポジトリから抽出した実測値:
#   skills=123, families=6
# 公開ページの掲載値 (116 / 7) ではない。
# 掲載値に退行したらこのテストが落ちる。

setup() {
  load '../helper.bash'
}

@test "catalog: snapshot reports 123 skills" {
  run run_iso skills summary
  [ "$status" -eq 0 ]
  assert_output_contains '123'
}

@test "catalog: snapshot reports 6 capability families" {
  run run_iso skills summary
  [ "$status" -eq 0 ]
  assert_output_contains '能力ファミリー'
  assert_output_contains '6'
}

@test "catalog: snapshot data source is declared explicitly" {
  run run_iso skills summary
  assert_output_contains '出荷時スナップショット'
  # 実測でないことを隠さない (evidence boundary)
  assert_output_contains '実測ではなくスナップショット値です'
}

@test "catalog: family detail lists the planner role for plan_and_decide" {
  run run_iso skills family plan_and_decide
  [ "$status" -eq 0 ]
  assert_output_contains 'plan_and_decide'
  assert_output_contains 'planner'
}

@test "catalog: family list includes all six verified families" {
  run run_iso skills show
  [ "$status" -eq 0 ]
  assert_output_contains 'plan_and_decide'
  assert_output_contains 'learn_and_gather'
  assert_output_contains 'retain_knowledge'
  assert_output_contains 'create_materials_and_visuals'
  assert_output_contains 'delegate_coding_and_ship'
  assert_output_contains 'operate_and_observe'
}

@test "catalog: list returns many skill names from snapshot" {
  run run_iso skills list
  [ "$status" -eq 0 ]
  assert_output_contains 'accessibility-audit'
  assert_output_contains 'code-review'
}

@test "catalog: search filters skill names" {
  run run_iso skills search memory
  [ "$status" -eq 0 ]
  assert_output_contains 'memory'
}

@test "catalog: snapshot file is valid JSON" {
  run jq empty "$PROJECT_ROOT/config/omh-capability-catalog.json"
  [ "$status" -eq 0 ]
}

@test "catalog: snapshot skill count matches file contents" {
  local n
  n="$(jq -r '.skills | length' "$PROJECT_ROOT/config/omh-capability-catalog.json")"
  [ "$n" -eq 123 ]
}

# ---------------------------------------------------------------
# 回帰テスト: 実レイアウトは「役割/スキル名/SKILL.md」の3段である。
# 過去に「/*/SKILL.md」(1段) の glob で検出していたため、OMH を
# setup 済みでも「未 setup」と誤判定していた。
# ---------------------------------------------------------------

@test "catalog: detects nested role/skill/SKILL.md layout (depth 3)" {
  local d; d="$(mktemp -d)"
  # 実レイアウトを再現: role/skill-name/SKILL.md
  mkdir -p "${d}/planner/omh-apps" "${d}/ultrawork/ulw-plan" "${d}/operator/omh-ops"
  : > "${d}/planner/omh-apps/SKILL.md"
  : > "${d}/ultrawork/ulw-plan/SKILL.md"
  : > "${d}/operator/omh-ops/SKILL.md"

  run bash -c "
    source '${PROJECT_ROOT}/lib/common.sh'
    source '${PROJECT_ROOT}/lib/json.sh'
    source '${PROJECT_ROOT}/lib/skills-catalog.sh'
    omh_skill_count_in '$d'
  "
  rm -rf "$d"

  [ "$status" -eq 0 ]
  [ "$output" = "3" ]
}

@test "catalog: deeper nesting is counted too (not depth-limited)" {
  local d; d="$(mktemp -d)"
  mkdir -p "${d}/a/b/c/deep-skill"
  : > "${d}/a/b/c/deep-skill/SKILL.md"

  run bash -c "
    source '${PROJECT_ROOT}/lib/common.sh'
    source '${PROJECT_ROOT}/lib/json.sh'
    source '${PROJECT_ROOT}/lib/skills-catalog.sh'
    omh_skill_count_in '$d'
  "
  rm -rf "$d"

  [ "$output" = "1" ]
}

@test "catalog: role dirs are derived from the real layout" {
  local d; d="$(mktemp -d)"
  mkdir -p "${d}/planner/s1" "${d}/reviewer/s2"
  : > "${d}/planner/s1/SKILL.md"
  : > "${d}/reviewer/s2/SKILL.md"

  run bash -c "
    source '${PROJECT_ROOT}/lib/common.sh'
    source '${PROJECT_ROOT}/lib/json.sh'
    source '${PROJECT_ROOT}/lib/skills-catalog.sh'
    OMH_SKILLS_DIR='$d'
    omh_role_dirs_in '$d'
  "
  rm -rf "$d"

  assert_output_contains 'planner'
  assert_output_contains 'reviewer'
}

# hermes skills list の集計行を正しく解釈できること。
# 実測値: '0 hub-installed, 53 builtin, 123 local — 176 enabled, 0 disabled'
@test "catalog: parses hermes skills list totals line" {
  local d; d="$(mktemp -d)"
  mkdir -p "${d}/bin"
  cat > "${d}/bin/hermes" <<'STUB'
#!/usr/bin/env bash
if [[ "${1:-}" == "skills" ]]; then
  echo "some header"
  echo "0 hub-installed, 53 builtin, 123 local — 176 enabled, 0 disabled"
fi
STUB
  chmod +x "${d}/bin/hermes"

  run bash -c "
    source '${PROJECT_ROOT}/lib/common.sh'
    source '${PROJECT_ROOT}/lib/json.sh'
    export PATH="$d/bin:$PATH"
    source '${PROJECT_ROOT}/lib/paths.sh'
    source '${PROJECT_ROOT}/lib/skills-catalog.sh'
    hermes_skill_totals
  "
  rm -rf "$d"

  [ "$status" -eq 0 ]
  assert_output_contains '176 enabled'
  assert_output_contains '123 local'
}

@test "catalog: extracts enabled count from totals" {
  local d; d="$(mktemp -d)"
  mkdir -p "${d}/bin"
  cat > "${d}/bin/hermes" <<'STUB'
#!/usr/bin/env bash
echo "0 hub-installed, 53 builtin, 123 local — 176 enabled, 0 disabled"
STUB
  chmod +x "${d}/bin/hermes"

  run bash -c "
    source '${PROJECT_ROOT}/lib/common.sh'
    source '${PROJECT_ROOT}/lib/json.sh'
    export PATH="$d/bin:$PATH"
    source '${PROJECT_ROOT}/lib/paths.sh'
    source '${PROJECT_ROOT}/lib/skills-catalog.sh'
    hermes_enabled_skill_count
  "
  rm -rf "$d"

  [ "$output" = "176" ]
}
