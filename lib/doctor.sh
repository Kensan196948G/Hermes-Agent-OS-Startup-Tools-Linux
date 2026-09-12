#!/usr/bin/env bash
# ============================================================
# doctor.sh — 統合診断
#
# 設計上の約束 (evidence boundaries):
#   各チェックは PASS / WARN / FAIL / SKIP を明示し、
#   「未確認」を PASS と偽らない。判定できないものは SKIP とする。
#   最終行に recommended_next_action を必ず出す。
# ============================================================

if [[ -n "${__HERMESOS_DOCTOR_SH:-}" ]]; then
  return 0
fi
__HERMESOS_DOCTOR_SH=1

# 推奨次アクションを組み立てるためのグローバル
DOCTOR_NEXT_ACTIONS=()
_doctor_next() { DOCTOR_NEXT_ACTIONS+=("$1"); }

# check_os
doctor_check_os() {
  printf '%s[1] 実行環境%s\n' "$C_BOLD" "$C_RESET"
  if os_is_linux; then
    check_pass "Linux native: $(os_summary)"
  else
    check_fail "Linux 以外: $(uname -s) — このツールの対象外"
    _doctor_next "Linux 上で実行してください (WSL2 は Linux 側で)"
    return 1
  fi
  if os_is_root; then
    check_warn "root で実行中。per-user 前提の経路 (per-user install) と混在しやすい"
  else
    check_pass "非 root 実行 (per-user install 経路)"
  fi
  return 0
}

# check_prereq
doctor_check_prereq() {
  printf '\n%s[2] 前提コマンド%s\n' "$C_BOLD" "$C_RESET"
  local c missing=()
  for c in bash curl git; do
    if has_cmd "$c"; then check_pass "$c"; else check_fail "$c (必須)"; missing+=("$c"); fi
  done
  for c in jq tmux; do
    if has_cmd "$c"; then check_pass "$c"; else check_warn "$c (推奨 — 一部機能が制限)"; fi
  done
  if [[ "${#missing[@]}" -gt 0 ]]; then
    _doctor_next "欠落した必須コマンドを導入: ${missing[*]}"
    return 1
  fi
  return 0
}

# check_hermes
doctor_check_hermes() {
  printf '\n%s[3] Hermes 本体%s\n' "$C_BOLD" "$C_RESET"

  if ! hermes_installed; then
    check_fail "hermes コマンドが無い"
    if [[ -d "$HERMES_CODE_DIR" ]]; then
      check_warn "コードは存在するがコマンドが無い: $HERMES_CODE_DIR"
    fi
    _doctor_next "メニュー [1] から Hermes 本体を導入"
    return 1
  fi
  check_pass "hermes: $(hermes_install_status)"
  hermes_path_hint || _doctor_next "PATH に ~/.local/bin を追加"

  # データディレクトリ
  if [[ -d "$HERMES_HOME" ]]; then
    check_pass "HERMES_HOME が存在: $HERMES_HOME"
  else
    check_warn "HERMES_HOME が未作成: $HERMES_HOME (初回起動時に作成される)"
  fi

  # config.yaml
  if [[ -f "$HERMES_CONFIG" ]]; then
    check_pass "config.yaml が存在: $HERMES_CONFIG"
    if grep -qE '^[[:space:]]*(api_key|token|secret)' "$HERMES_CONFIG" 2>/dev/null; then
      check_warn "config.yaml に認証情報らしきキーがある。権限 (600) を確認してください"
    fi
  else
    check_warn "config.yaml が無い。hermes setup または hermes model で作成してください"
    _doctor_next "hermes setup または hermes model でプロバイダを設定"
  fi

  # 認証情報
  if [[ -d "$HERMES_HOME" ]] && compgen -G "$HERMES_HOME/*auth*" >/dev/null 2>&1; then
    check_pass "認証情報ファイルを検出"
  elif [[ -f "$HERMES_CONFIG" ]]; then
    check_skip "認証情報の有無は本ツールから断定しない (hermes doctor で確認)"
  else
    check_skip "認証情報: config 未作成のため未評価"
  fi
  return 0
}

# check_omh
doctor_check_omh() {
  printf '\n%s[4] Oh My Hermes (OMH)%s\n' "$C_BOLD" "$C_RESET"

  if ! omh_installed; then
    check_fail "omh コマンドが無い"
    _doctor_next "メニュー [2] から OMH を導入"
    return 1
  fi
  check_pass "omh: $(omh_install_status)"

  # setup 済み判定は managed artifact の実在で行う
  if [[ -d "$OMH_SKILLS_DIR" ]]; then
    local n; n="$(find "$OMH_SKILLS_DIR" -name 'SKILL.md' 2>/dev/null | wc -l | tr -d ' ')"
    check_pass "$OMH_SKILLS_DIR が存在 (SKILL.md: ${n} 件)"
  else
    check_warn "$OMH_SKILLS_DIR が無い — omh setup が未実行の可能性"
    _doctor_next "omh setup を実行 (メニュー [2])"
  fi

  if [[ -d "$HERMES_OMH_PLUGIN_DIR" ]]; then
    check_pass "plugin bridge が存在: $HERMES_OMH_PLUGIN_DIR"
  else
    check_warn "plugin bridge が無い: $HERMES_OMH_PLUGIN_DIR — omh setup が未実行の可能性"
    _doctor_next "omh setup を実行 (plugin 登録)"
  fi

  # Hermes config が skills.external_dirs に OMH skills を含むか
  if [[ -f "$HERMES_CONFIG" ]]; then
    if skills_dir_registered; then
      check_pass "config.yaml の skills.external_dirs に $OMH_SKILLS_DIR を検出"
    else
      check_warn "config.yaml に $OMH_SKILLS_DIR が見つからない — OMH skills が読まれない可能性"
      _doctor_next "omh setup を再実行して skills.external_dirs を登録"
    fi
  else
    check_skip "skills.external_dirs: config.yaml が無いため未評価"
  fi

  if [[ -f "$OMH_MODEL_CHAINS" ]]; then
    if json_valid "$OMH_MODEL_CHAINS"; then
      check_pass "model-chains.json が有効な JSON: $OMH_MODEL_CHAINS"
    else
      check_warn "model-chains.json が不正な JSON: $OMH_MODEL_CHAINS"
      _doctor_next "model-chains.json を修正 (ルーティングが既定に戻る)"
    fi
  else
    check_warn "model-chains.json が無い: $OMH_MODEL_CHAINS (出荷時既定が適用される)"
  fi
  return 0
}

# check_profiles — profile/bot ごとの登録状態
doctor_check_profiles() {
  printf '\n%s[5] プロファイル / bot ホーム%s\n' "$C_BOLD" "$C_RESET"
  if [[ ! -d "$HERMES_PROFILES_DIR" ]]; then
    check_skip "profiles ディレクトリ無し: $HERMES_PROFILES_DIR"
    return 0
  fi

  local found=0 p name
  for p in "$HERMES_PROFILES_DIR"/*; do
    [[ -d "$p" ]] || continue
    found=1
    name="$(basename "$p")"
    if [[ -d "${p}/plugins/omh" ]]; then
      check_pass "profile '$name': OMH plugin 登録あり"
    else
      check_warn "profile '$name': OMH plugin 登録なし (omh update で再適用される)"
    fi
  done
  [[ "$found" -eq 0 ]] && check_skip "profile が1つも無い"
  return 0
}

# check_routing — モデルルーティングの準備度 (要約のみ)
#   confirmed が 0 のとき「未確定」を WARN で明示する。
#   ルーティング未確定は起動を妨げないが、委譲先が未証明であることは
#   完了報告の前に知っておく必要がある。
doctor_check_routing() {
  printf '\n%s[6] モデルルーティング準備度%s\n' "$C_BOLD" "$C_RESET"
  if ! omh_installed; then
    check_skip "omh 未導入のためスキップ"
    return 0
  fi

  local json
  json="$(routing_status_json)" || json=""
  if [[ -z "$json" ]] || ! printf '%s' "$json" | jq empty >/dev/null 2>&1; then
    check_skip "上流の model-routing status を取得できません"
    log_dim "  手動確認: omh coding model-routing status"
    return 0
  fi

  local confirmed discovered status
  confirmed="$(printf '%s' "$json" | jq -r '.models.confirmed | length')"
  discovered="$(printf '%s' "$json" | jq -r '.models.discovered_only | length')"
  status="$(printf '%s' "$json" | jq -r '.status // "unknown"')"

  if [[ "$confirmed" -gt 0 ]]; then
    check_pass "confirmed $confirmed 件 (status: $status)"
  else
    check_warn "confirmed 0 件 — ルーティング未確定 (discovered_only $discovered 件は実行証明ではない)"
    _doctor_next "モデル委譲を使う前に確定: omh model-chains interview または omh coding model-routing status"
  fi

  local aliases
  aliases="$(printf '%s' "$json" | jq -r '.hermes.status // "unknown"')"
  if [[ "$aliases" == "aliases_unset" ]]; then
    check_warn "Hermes aliases 未設定 (aliases_unset)"
  else
    check_pass "Hermes aliases: $aliases"
  fi

  local owner
  owner="$(printf '%s' "$json" | jq -r '.owner_learning.status // "unknown"')"
  [[ "$owner" == "missing" ]] && check_dim_ok "owner learning: missing (学習履歴なし)" || check_pass "owner learning: $owner"
  return 0
}

# check_omh_doctor — upstream 自身の doctor に最終判断を委ねる
doctor_check_omh_doctor() {
  printf '\n%s[7] 上流 doctor (omh doctor)%s\n' "$C_BOLD" "$C_RESET"
  if ! omh_installed; then
    check_skip "omh 未導入のためスキップ"
    return 0
  fi
  if [[ "$DRY_RUN" == "1" ]]; then
    check_skip "DRY-RUN のため実行しない"
    return 0
  fi
  log_dim "  'omh doctor' を実行します (上流の権威ある診断)..."
  printf '\n'
  if "$(omh_cmd)" doctor; then
    check_pass "omh doctor が成功"
  else
    check_fail "omh doctor が失敗 — 上流の出力を確認してください"
    _doctor_next "omh doctor の出力にある recommended_next_action に従う"
  fi
  return 0
}

# doctor_run [--quick]
doctor_run() {
  local quick=0
  [[ "${1:-}" == "--quick" ]] && quick=1

  print_banner
  printf '%s統合診断 (doctor)%s\n' "$C_BOLD" "$C_RESET"
  log_dim "  対象: $(os_summary)"
  log_dim "  HERMES_HOME=$HERMES_HOME"
  log_dim "  OMH_HOME=$OMH_HOME"

  doctor_check_os     || true
  doctor_check_prereq || true
  doctor_check_hermes || true
  doctor_check_omh    || true
  doctor_check_profiles || true
  doctor_check_routing  || true
  [[ "$quick" -eq 0 ]] && doctor_check_omh_doctor || true

  printf '\n%s────────────────────────────────────────────%s\n' "$C_DIM" "$C_RESET"
  printf '%s結果%s  ' "$C_BOLD" "$C_RESET"
  printf '%sPASS=%d%s  %sWARN=%d%s  %sFAIL=%d%s  %sSKIP=%d%s\n' \
    "$C_GREEN" "$CHECKS_PASS" "$C_RESET" \
    "$C_YELLOW" "$CHECKS_WARN" "$C_RESET" \
    "$C_RED" "$CHECKS_FAIL" "$C_RESET" \
    "$C_DIM" "$CHECKS_SKIP" "$C_RESET"

  # recommended_next_action — 未検証の断定を避け、根拠のある行動だけ出す
  printf '\n%srecommended_next_action%s\n' "$C_BOLD" "$C_RESET"
  if [[ "${#DOCTOR_NEXT_ACTIONS[@]}" -eq 0 ]]; then
    printf '  %s→ 対応不要。Hermes を起動できます: hermes%s\n' "$C_GREEN" "$C_RESET"
  else
    local a
    for a in "${DOCTOR_NEXT_ACTIONS[@]}"; do
      printf '  %s→%s %s\n' "$C_YELLOW" "$C_RESET" "$a"
    done
  fi
  printf '\n'

  [[ "$CHECKS_FAIL" -eq 0 ]] && return 0 || return 1
}
