#!/usr/bin/env bash
# ============================================================
# skills-catalog.sh — スキルカタログ / ワークフロー / 能力ファミリー
#
# データ源の優先順位 (evidence boundaries):
#   1. 実インストール済みの ~/.omh/skills  (実測 — 最も信頼できる)
#   2. config/omh-capability-catalog.json  (出荷時スナップショット)
#   3. どちらも無ければ SKIP と明示する (推測で件数を主張しない)
#
# 確認済みの出荷時値 (omh source から抽出):
#   installable_skill_names: 123
#   capability families    : 6
#   builtin_definitions    : 128
# 公開ページは 116 skills / 9 workflows / 7 families / 8 languages を
# 掲げているが、リポジトリ実測と一致しない。本ツールは実測を表示する。
# ============================================================

if [[ -n "${__HERMESOS_SKILLS_CATALOG_SH:-}" ]]; then
  return 0
fi
__HERMESOS_SKILLS_CATALOG_SH=1

CATALOG_FILE="${HERMESOS_ROOT}/config/omh-capability-catalog.json"

# omh_skill_files — インストール済み SKILL.md を1行ずつ
#
#   重要 (実測で判明した事実):
#     ~/.omh/skills の実レイアウトは「役割/スキル名/SKILL.md」の3段である。
#       例: ~/.omh/skills/ultrawork/ulw-plan/SKILL.md
#           ~/.omh/skills/planner/omh-apps/SKILL.md
#     最上位は 9 個の役割ディレクトリ (planner, researcher, builder,
#     reviewer, operator, memory-keeper, tracker, guide, handoff-guide)。
#     したがって「/*/SKILL.md」のような固定深さの glob は使えない。
#     深さに依存しない find を使うこと。
omh_skill_files() {
  [[ -d "$OMH_SKILLS_DIR" ]] || return 0
  find "$OMH_SKILLS_DIR" -name 'SKILL.md' -type f 2>/dev/null | sort
}

# omh_skill_files_in <dir> — 任意ディレクトリ版 (テスト可能性のため分離)
omh_skill_files_in() {
  local dir="$1"
  [[ -d "$dir" ]] || return 0
  find "$dir" -name 'SKILL.md' -type f 2>/dev/null | sort
}

# omh_skill_count_in <dir> — 任意ディレクトリの実測件数
omh_skill_count_in() {
  local n; n="$(omh_skill_files_in "$1" | grep -c . || true)"
  printf '%s' "${n:-0}"
}

# omh_role_dirs_in <dir> — 任意ディレクトリの役割ディレクトリ
omh_role_dirs_in() {
  local dir="$1"
  [[ -d "$dir" ]] || return 0
  find "$dir" -mindepth 1 -maxdepth 1 -type d 2>/dev/null \
    | while IFS= read -r d; do basename "$d"; done | sort
}

# omh_skill_count_installed — OMH が配置した実測件数
omh_skill_count_installed() {
  omh_skill_count_in "$OMH_SKILLS_DIR"
}

# hermes_skill_totals — Hermes 自身に問い合わせた集計 (権威ある値)
#
#   'hermes skills list' の最終行は次の形である:
#     0 hub-installed, 53 builtin, 123 local — 176 enabled, 0 disabled
#
#   重要 (実測で判明した区別):
#     * OMH の 123 skills は ~/.omh/skills 配下に「役割/スキル名/」で置かれる。
#     * Hermes 側の「category」(20 種) は Hermes 自身の分類であり、
#       OMH の役割ディレクトリとは別の軸である。混同してはならない。
#     * Hermes の総数は builtin と local を合わせた数で、
#       ディスク上の合計 (58 + 123 = 181) とは重複の分だけ異なる。
#
#   失敗時は空を返し、呼び出し側は OMH 分のみを表示する。
hermes_skill_totals() {
  hermes_installed || return 0
  [[ "$DRY_RUN" == "1" ]] && return 0
  timeout 60 "$(hermes_cmd)" skills list 2>/dev/null \
    | grep -oE '[0-9]+ hub-installed, [0-9]+ builtin, [0-9]+ local — [0-9]+ enabled, [0-9]+ disabled' \
    | tail -1
}

# hermes_enabled_skill_count — Hermes が見ている enabled 総数 (取れなければ空)
hermes_enabled_skill_count() {
  # 'local x="$(...)"' は command substitution の失敗を伝播させ set -e で
  # 落ちる。宣言と代入を分離し、失敗時は空を返して継続する。
  local line
  line="$(hermes_skill_totals)" || line=""
  [[ -z "$line" ]] && return 0
  printf '%s' "$line" | grep -oE '[0-9]+ enabled' | grep -oE '[0-9]+'
}

# omh_role_dirs — 役割ディレクトリ名を1行ずつ (実レイアウト由来)
omh_role_dirs() {
  omh_role_dirs_in "$OMH_SKILLS_DIR"
}

# omh_role_of_skill <skill-name> — そのスキルが属する役割を返す
omh_role_of_skill() {
  local name="$1" f
  while IFS= read -r f; do
    [[ "$(basename "$(dirname "$f")")" == "$name" ]] || continue
    basename "$(dirname "$(dirname "$f")")"
    return 0
  done < <(omh_skill_files)
  return 1
}

# catalog_source — 'installed' | 'snapshot' | 'none'
catalog_source() {
  if [[ "$(omh_skill_count_installed)" -gt 0 ]]; then
    printf 'installed'
  elif [[ -f "$CATALOG_FILE" ]]; then
    printf 'snapshot'
  else
    printf 'none'
  fi
}

# installed_skill_count — 実測値
installed_skill_count() {
  omh_skill_count_installed
}

# snapshot_skill_count
snapshot_skill_count() {
  json_get "$CATALOG_FILE" '.skills | length' "0"
}

# effective_skill_count — 表示に使う件数と、その出所
effective_skill_count() {
  case "$(catalog_source)" in
    installed) installed_skill_count ;;
    snapshot)  snapshot_skill_count ;;
    *)         printf '0' ;;
  esac
}

# catalog_families — family id を1行ずつ
catalog_families() {
  json_get "$CATALOG_FILE" '.families[].id' "" 2>/dev/null || true
}

# catalog_family_count
catalog_family_count() {
  json_get "$CATALOG_FILE" '.families | length' "0"
}

# workflow_skills — OMH の workflow 系スキル名を1行ずつ
#   installed なら SKILL.md の tags を見る。snapshot なら family の
#   primary_workflows を union する。
workflow_skills() {
  if [[ "$(catalog_source)" == "installed" ]]; then
    local f
    while IFS= read -r f; do
      [[ -z "$f" ]] && continue
      grep -qE 'tags:.*\bworkflow\b' "$f" 2>/dev/null && basename "$(dirname "$f")"
    done < <(omh_skill_files)
  elif [[ -f "$CATALOG_FILE" ]]; then
    jq -r '[.families[].primary_workflows[]] | unique | .[]' "$CATALOG_FILE" 2>/dev/null
  fi
}

workflow_skill_count() {
  local n; n="$(workflow_skills | grep -c . || true)"
  printf '%s' "${n:-0}"
}

# catalog_summary — カタログ全体の要約表示
catalog_summary() {
  local src; src="$(catalog_source)"

  printf '%sスキルカタログ%s\n' "$C_BOLD" "$C_RESET"

  case "$src" in
    installed)
      printf '  %-22s %s\n' "データ源" "実インストール ($OMH_SKILLS_DIR)"
      printf '  %-22s %s\n' "スキル (実測)" "$(installed_skill_count)"
      ;;
    snapshot)
      printf '  %-22s %s\n' "データ源" "出荷時スナップショット ($CATALOG_FILE)"
      printf '  %-22s %s\n' "スキル (snapshot)" "$(snapshot_skill_count)"
      log_warn "OMH が未 setup のため、実測ではなくスナップショット値です。"
      log_dim "  正確な実測値は omh setup 後に得られます。"
      ;;
    *)
      printf '  %-22s %s\n' "データ源" "なし"
      log_warn "カタログを取得できません (OMH 未導入かつ snapshot 無し)。"
      return 1
      ;;
  esac

  printf '  %-22s %s\n' "能力ファミリー" "$(catalog_family_count)"

  # 実インストール時の実レイアウトは「役割/スキル名/SKILL.md」である。
  # 役割ごとの内訳はカタログ理解の助けになるため実測で表示する。
  if [[ "$src" == "installed" ]]; then
    printf '\n%sOMH が配置した skills (役割ディレクトリ別)%s\n' "$C_BOLD" "$C_RESET"
    printf '  %-22s %s\n' "OMH skills 合計" "$(installed_skill_count)"
    local r cnt
    while IFS= read -r r; do
      [[ -z "$r" ]] && continue
      cnt="$(find "${OMH_SKILLS_DIR}/${r}" -name 'SKILL.md' -type f 2>/dev/null | grep -c . || true)"
      printf '  %-18s %s\n' "$r" "${cnt:-0}"
    done < <(omh_role_dirs)

    # Hermes 自身の集計 (権威ある総数) と、役割/category の軸の違いを明示する。
    local totals enabled
    totals="$(hermes_skill_totals)"
    enabled="$(hermes_enabled_skill_count)"
    if [[ -n "$enabled" ]]; then
      printf '\n%sHermes が見ている総数 (hermes skills list 実測)%s\n' "$C_BOLD" "$C_RESET"
      printf '  %s\n' "$totals"
      log_dim "  builtin と local を合わせた数。ディスク上の合計とは重複の分だけ異なる。"
    else
      printf '\n'
      check_skip "Hermes 側の総数は未取得 (hermes 未起動または skills list 失敗)"
      log_dim "  取得: hermes skills list"
    fi

    printf '\n%s役割 と category は別の軸である%s\n' "$C_BOLD" "$C_RESET"
    log_dim "  役割 (=ディレクトリ): $(omh_role_dirs | grep -c .) 種 — OMH が skills を置く場所"
    log_dim "  category          : Hermes 自身の分類 (TUI の category 列に出る)"
    log_dim "  同じ 1 スキルが「役割」と「category」の両方の属性を持つ。混同しないこと。"
  fi

  if [[ "$src" == "installed" ]]; then
    printf '\n  %s公開ページの掲載値との差%s\n' "$C_DIM" "$C_RESET"
    printf '  %s  公開ページ: 116 skills / 7 families%s\n' "$C_DIM" "$C_RESET"
    printf '  %s  本ツール実測: OMH %s skills / %s roles / %s families%s\n' \
      "$C_DIM" "$(installed_skill_count)" "$(omh_role_dirs | grep -c .)" "$(catalog_family_count)" "$C_RESET"
    log_dim "  掲載値ではなく実測を表示しています (evidence boundary)。"
  fi
  return 0
}

# catalog_search <pattern> — スキル名の部分一致検索
catalog_search() {
  local pattern="$1"
  case "$(catalog_source)" in
    installed)
      omh_skill_files | while IFS= read -r f; do basename "$(dirname "$f")"; done \
        | grep -i -- "$pattern" | sort
      ;;
    snapshot)
      jq -r --arg p "$pattern" '.skills[] | select(test($p; "i"))' "$CATALOG_FILE" 2>/dev/null
      ;;
    *) return 1 ;;
  esac
}

# catalog_family_detail <family-id>
catalog_family_detail() {
  local fid="$1"
  [[ -f "$CATALOG_FILE" ]] || { log_error "カタログがありません: $CATALOG_FILE"; return 1; }
  jq -r --arg id "$fid" '
    .families[] | select(.id == $id) |
    "  id            : \(.id)
  label         : \(.label)
  owner_role    : \(.owner_role)
  use_for       : \(.use_for)
  workflows     : \(.primary_workflows | join(", "))"
  ' "$CATALOG_FILE" 2>/dev/null || { log_error "family が見つかりません: $fid"; return 1; }
}

# catalog_show — 全ファミリーを一覧
catalog_show() {
  [[ -f "$CATALOG_FILE" ]] || { log_error "カタログがありません: $CATALOG_FILE"; return 1; }
  catalog_summary || true
  printf '\n%s能力ファミリー一覧%s\n' "$C_BOLD" "$C_RESET"
  jq -r '.families[] | "  \(.id)\n    \(.label)  [role: \(.owner_role)]\n    \(.use_for)\n    workflows: \(.primary_workflows | length) 件"' \
    "$CATALOG_FILE" 2>/dev/null
}

# catalog_list_skills — 全スキル名
catalog_list_skills() {
  case "$(catalog_source)" in
    installed)
      omh_skill_files | while IFS= read -r f; do basename "$(dirname "$f")"; done | sort
      ;;
    snapshot)  jq -r '.skills[]' "$CATALOG_FILE" 2>/dev/null ;;
    *) return 1 ;;
  esac
}
