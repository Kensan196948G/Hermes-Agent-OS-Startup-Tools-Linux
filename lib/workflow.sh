#!/usr/bin/env bash
# ============================================================
# workflow.sh — ワークフロー集 / 役割 (roles)
#
# ワークフロー集の実体は OMH の workflow スキルである。
# 本ツールは「どの仕事にどのワークフローを使うか」の目印と、
# 標準の工程順 (計画→調査→作成→実装引き継ぎ→運用→記憶) を提示する。
#
# 事実: roles/ には planner, researcher, builder, reviewer, operator,
#       memory-keeper, tracker, guide, handoff-guide が定義されている。
# ============================================================

if [[ -n "${__HERMESOS_WORKFLOW_SH:-}" ]]; then
  return 0
fi
__HERMESOS_WORKFLOW_SH=1

readonly WORKFLOW_STAGES=(
  "計画:plan_and_decide"
  "調査:learn_and_gather"
  "記憶:retain_knowledge"
  "作成:create_materials_and_visuals"
  "実装引き継ぎ:delegate_coding_and_ship"
  "運用:operate_and_observe"
)

# workflow_roles — OMH の役割一覧 (出荷時定義)
workflow_roles() {
  cat <<'ROLES'
planner        計画を立てる。実装しない。
researcher     根拠を集める。結論を急がない。
builder        実装する。計画の範囲を超えない。
reviewer       検証する。実装者とは別の目で見る。
operator       運用する。変更を観測する。
memory-keeper  記憶を保つ。判断理由を残す。
tracker        進捗を追う。停滞を可視化する。
guide          利用者を案内する。判断は委ねる。
handoff-guide  引き継ぐ。未解決を明示する。
ROLES
}

# workflow_stages_text — 標準工程の提示
workflow_stages_text() {
  cat <<'STAGES'
## ワークフロー集 — 標準工程

依頼を受けたら、いきなり実装・回答しない。次の工程を踏む。

  1. 計画 (plan_and_decide)
     ゴールが曖昧なら深掘りする。成功条件を先に決める。
  2. 調査 (learn_and_gather)
     事実を集める。推測と観測を分ける (evidence boundaries)。
  3. 作成 (create_materials_and_visuals)
     成果物を作る。作っただけなら PREPARED であり、検証ではない。
  4. 実装引き継ぎ (delegate_coding_and_ship)
     実装は委任する。範囲と受け入れ条件を明示して渡す。
  5. 運用 (operate_and_observe)
     変更後の状態を観測する。観測できなければ完了ではない。
  6. 記憶 (retain_knowledge)
     判断と理由と未解決を残す。次の作業が同じ調査を繰り返さないように。

不確実性が高い場合は 1→2→3→5 を Loop Engineering で反復する。
STAGES
}

# workflow_for_task <task-description> — 仕事から適切な family を推定
#   キーワードベースの粗い振り分け。断定ではなく候補提示。
workflow_for_task() {
  local task; task="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  local fam=""

  case "$task" in
    *plan*|*設計*|*計画*|*要件*|*方針*|*decision*|*判断*) fam="plan_and_decide" ;;
    *調査*|*research*|*調べ*|*論文*|*比較*|*検索*)       fam="learn_and_gather" ;;
    *記憶*|*memory*|*引き継*|*handoff*|*記録*)           fam="retain_knowledge" ;;
    *資料*|*スライド*|*ポスター*|*図*|*デザイン*|*deck*)  fam="create_materials_and_visuals" ;;
    *実装*|*コード*|*code*|*修正*|*バグ*|*テスト*|*api*)  fam="delegate_coding_and_ship" ;;
    *運用*|*監視*|*デプロイ*|*障害*|*ops*|*deploy*)       fam="operate_and_observe" ;;
    *) fam="" ;;
  esac

  if [[ -z "$fam" ]]; then
    log_dim "  候補を判定できませんでした。計画 (plan_and_decide) から始めてください。"
    return 1
  fi
  printf '%s' "$fam"
}

# workflow_catalog_view — workflow スキル一覧と family 対応
workflow_catalog_view() {
  printf '%sワークフロー集%s\n' "$C_BOLD" "$C_RESET"
  printf '  %-22s %s\n' "データ源" "$(catalog_source)"
  printf '  %-22s %s\n' "workflow スキル数" "$(workflow_skill_count)"

  printf '\n%s工程とファミリーの対応%s\n' "$C_BOLD" "$C_RESET"
  local entry stage fid
  for entry in "${WORKFLOW_STAGES[@]}"; do
    stage="${entry%%:*}"
    fid="${entry##*:}"
    printf '\n  %s%s%s  →  %s\n' "$C_BOLD" "$stage" "$C_RESET" "$fid"
    if [[ -f "$CATALOG_FILE" ]]; then
      jq -r --arg id "$fid" \
        '.families[] | select(.id == $id) | .primary_workflows[] | "      - \(.)"' \
        "$CATALOG_FILE" 2>/dev/null || log_dim "      (family 定義を取得できません)"
    fi
  done

  printf '\n%s役割%s\n' "$C_BOLD" "$C_RESET"
  workflow_roles | sed 's/^/  /'
  return 0
}

# workflow_write_catalog <dest> — カタログを Markdown として書き出す
workflow_write_catalog() {
  local dest="${1:-${HERMES_HOME}/WORKFLOWS.md}"
  mkdir -p "$(dirname "$dest")"
  {
    printf '# ワークフロー集 — HermesAgentOS StartUpTools\n\n'
    printf '> 生成: %s / データ源: %s\n\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$(catalog_source)"
    workflow_stages_text
    printf '\n'
    workflow_roles
    printf '\n## ファミリー別 workflow スキル\n\n'
    if [[ -f "$CATALOG_FILE" ]]; then
      jq -r '.families[] | "### \(.id) — \(.label)\n\n\(.use_for)\n\n役割: `\(.owner_role)`\n\n" + ([.primary_workflows[] | "- `\(.)`"] | join("\n")) + "\n"' \
        "$CATALOG_FILE" 2>/dev/null
    fi
  } > "$dest"
  printf '%s' "$dest"
}
