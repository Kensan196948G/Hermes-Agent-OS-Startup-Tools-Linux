#!/usr/bin/env bash
# ============================================================
# profiles.sh — Hermes profile / bot ホームの管理
#
# 事実 (upstream で確認):
#   profile ホーム: ~/.hermes/profiles/<name>/
#   bot profile は setup / update 時に自動同期される。
#   後から作った bot は次回の omh update で bootstrap される。
#   確認: hermes -p <name> skills list
#   omh --hermes-home ~/.hermes/profiles/<name> uninstall --registration-only
#     で意図的に登録解除した profile は再登録されない。
# ============================================================

if [[ -n "${__HERMESOS_PROFILES_SH:-}" ]]; then
  return 0
fi
__HERMESOS_PROFILES_SH=1

# profiles_list — profile 名を1行ずつ
profiles_list() {
  [[ -d "$HERMES_PROFILES_DIR" ]] || return 0
  local p
  for p in "$HERMES_PROFILES_DIR"/*; do
    [[ -d "$p" ]] || continue
    basename "$p"
  done
}

profiles_count() {
  local n; n="$(profiles_list | grep -c . || true)"
  printf '%s' "${n:-0}"
}

# profile_omh_registered <name>
profile_omh_registered() {
  [[ -d "${HERMES_PROFILES_DIR}/$1/plugins/omh" ]]
}

# profiles_status — 一覧と OMH 登録状態
profiles_status() {
  printf '%sプロファイル / bot%s\n' "$C_BOLD" "$C_RESET"
  printf '  %-22s %s\n' "default profile" "$HERMES_HOME (常に存在)"

  if [[ ! -d "$HERMES_PROFILES_DIR" ]]; then
    log_dim "  追加プロファイルはまだありません: $HERMES_PROFILES_DIR"
    log_dim "  作成方法: hermes -p <name> ... で profile を指定して起動"
    log_dim "  注: OMH の 'profile detected' は上記 default profile を数えることがあります。"
    return 0
  fi

  local count; count="$(profiles_count)"
  if [[ "$count" == "0" ]]; then
    log_dim "  追加プロファイルはまだありません。"
    log_dim "  作成方法: hermes -p <name> ... で profile を指定して起動"
    return 0
  fi

  printf '\n  %-24s %-12s %s\n' "PROFILE" "OMH PLUGIN" "SKILLS DIR"
  local name
  while IFS= read -r name; do
    [[ -z "$name" ]] && continue
    local reg="no" sk="no"
    profile_omh_registered "$name" && reg="yes"
    [[ -d "${HERMES_PROFILES_DIR}/${name}/skills" ]] && sk="yes"
    printf '  %-24s %-12s %s\n' "$name" "$reg" "$sk"
  done < <(profiles_list)

  printf '\n%s確認コマンド%s\n' "$C_DIM" "$C_RESET"
  log_dim "  hermes -p <name> skills list"
  log_dim "  omh update   # 新規 profile を OMH に登録し直す"
  return 0
}

# profiles_sync — omh update による再登録を促す/実行する
profiles_sync() {
  if ! omh_installed; then
    log_error "OMH が未導入です。"
    return 1
  fi
  local count; count="$(profiles_count)"
  printf '  profile 数: %s\n' "$count"

  local unreg=() name
  while IFS= read -r name; do
    [[ -z "$name" ]] && continue
    profile_omh_registered "$name" || unreg+=("$name")
  done < <(profiles_list)

  if [[ "${#unreg[@]}" -eq 0 ]]; then
    log_ok "全 profile が OMH に登録済みです。"
    return 0
  fi

  log_warn "OMH 未登録の profile: ${unreg[*]}"
  log_dim "  'omh update' が未登録 profile を bootstrap します。"
  confirm "omh update を実行して同期しますか?" || { log_dim "中止しました。"; return 1; }
  update_omh
}

# profile_inspect <name>
profile_inspect() {
  local name="$1"
  local dir="${HERMES_PROFILES_DIR}/${name}"
  [[ -d "$dir" ]] || { log_error "profile がありません: $name"; return 1; }

  printf '%sprofile: %s%s\n' "$C_BOLD" "$name" "$C_RESET"
  printf '  %-22s %s\n' "home" "$dir"
  printf '  %-22s %s\n' "OMH plugin" "$(profile_omh_registered "$name" && printf yes || printf no)"
  printf '  %-22s %s\n' "config.yaml" "$([[ -f "$dir/config.yaml" ]] && printf yes || printf no)"
  printf '  %-22s %s\n' "skills" "$([[ -d "$dir/skills" ]] && find "$dir/skills" -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ' || printf 0)"

  if hermes_installed; then
    printf '\n%s上流に問い合わせ%s\n' "$C_DIM" "$C_RESET"
    "$(hermes_cmd)" -p "$name" skills list 2>/dev/null | head -20 || \
      log_dim "  'hermes -p $name skills list' の出力を取得できませんでした。"
  fi
  return 0
}
