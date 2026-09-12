#!/usr/bin/env bash
# ============================================================
# omh-install.sh — Oh My Hermes (OMH) の導入 / setup / 更新 / doctor
#
# 事実 (upstream で確認):
#   導入経路: curl install.sh / npm i -g oh-my-hermes / bun i -g oh-my-hermes
#             / brew install rlaope/tap/omh
#   導入後の必須手順: omh setup     (managed skills と Hermes 登録を行う)
#   検証:            omh doctor
#   更新:            omh update
#   setup が行う managed write:
#     - 生成 skills を ~/.omh/skills に配置
#     - Hermes config の skills.external_dirs にそのディレクトリを追加
#     - plugin bridge を ~/.hermes/plugins/omh に配置
#     - ~/.omh/routing/model-chains.json を seed
#   profile: ~/.hermes/profiles/<name> 配下の各ホームにも登録される
#
#   重要: 導入経路は「omh コマンドを置くだけ」。setup は別手順。
# ============================================================

if [[ -n "${__HERMESOS_OMH_INSTALL_SH:-}" ]]; then
  return 0
fi
__HERMESOS_OMH_INSTALL_SH=1

readonly OMH_INSTALL_CURL="https://raw.githubusercontent.com/rlaope/oh-my-hermes/main/install.sh"
readonly OMH_NPM_PKG="oh-my-hermes"

omh_install_status() {
  if omh_installed; then
    local v; v="$(omh_version)"
    printf 'installed (%s) at %s' "${v:-version unknown}" "$(command -v omh 2>/dev/null || printf '%s' "$OMH_BIN")"
  else
    printf 'NOT installed'
  fi
}

# omh_setup_status — setup 済みかどうかを managed artifact で判定
#   推測ではなく実在確認: skills ディレクトリ / plugin ディレクトリ
omh_setup_status() {
  local skills="no" plugin="no"
  [[ -d "$OMH_SKILLS_DIR" ]] && skills="yes"
  [[ -d "$HERMES_OMH_PLUGIN_DIR" ]] && plugin="yes"
  printf 'skills_dir=%s plugin=%s' "$skills" "$plugin"
}

omh_is_setup() {
  [[ -d "$OMH_SKILLS_DIR" ]] || return 1
  [[ -d "$HERMES_OMH_PLUGIN_DIR" ]] || return 1
  return 0
}

# install_omh — 選択された経路でコマンドを導入 (setup はしない)
install_omh() {
  local method="${1:-$HERMESOS_INSTALL_METHOD}"

  if omh_installed && [[ "${HERMESOS_FORCE:-0}" != "1" ]]; then
    log_ok "OMH コマンドは既に導入済みです: $(omh_install_status)"
    log_dim "  再導入する場合は HERMESOS_FORCE=1 を指定してください"
    return 0
  fi

  log_step "OMH コマンドを導入 (経路: $method)"

  # dry-run は何も導入しない。「完了しました」と報告してはならない。
  if [[ "$DRY_RUN" == "1" ]]; then
    case "$method" in
      npm)  printf '%s[DRY-RUN]%s npm install -g %s\n' "$C_CYAN" "$C_RESET" "$OMH_NPM_PKG" ;;
      bun)  printf '%s[DRY-RUN]%s bun install -g %s\n' "$C_CYAN" "$C_RESET" "$OMH_NPM_PKG" ;;
      brew) printf '%s[DRY-RUN]%s brew install rlaope/tap/omh\n' "$C_CYAN" "$C_RESET" ;;
      installer|curl|"")
            printf '%s[DRY-RUN]%s curl -fsSL %s | sh\n' "$C_CYAN" "$C_RESET" "$OMH_INSTALL_CURL" ;;
      *)    log_error "未知の導入経路: $method (installer|npm|bun|brew)"; return 1 ;;
    esac
    log_dim "  未実行です。実際に導入するには HERMESOS_DRY_RUN を外してください。"
    return 0
  fi

  case "$method" in
    npm)
      require_cmd npm "Node.js を導入してください" || return 1
      _omh_confirm_and_run "npm install -g $OMH_NPM_PKG" npm install -g "$OMH_NPM_PKG"
      ;;
    bun)
      require_cmd bun "bun を導入してください (https://bun.sh)" || return 1
      _omh_confirm_and_run "bun install -g $OMH_NPM_PKG" bun install -g "$OMH_NPM_PKG"
      ;;
    brew)
      require_cmd brew "Homebrew を導入してください" || return 1
      _omh_confirm_and_run "brew install rlaope/tap/omh" brew install rlaope/tap/omh
      ;;
    installer|curl|"")
      require_cmd curl "curl を導入してください" || return 1
      _omh_confirm_and_run "curl -fsSL $OMH_INSTALL_CURL | sh" \
        bash -c "curl -fsSL '$OMH_INSTALL_CURL' | sh"
      ;;
    *)
      log_error "未知の導入経路: $method (installer|npm|bun|brew)"
      return 1
      ;;
  esac

  if ! omh_installed; then
    log_warn "omh コマンドが PATH 上で確認できません。"
    log_dim "  installer が表示した絶対パスを使うか、そのディレクトリを PATH に追加してください。"
    log_dim "  これは「Hermes 登録に失敗した」証拠ではありません。"
    return 1
  fi

  log_ok "OMH コマンド導入を確認しました: $(omh_install_status)"
  return 0
}

_omh_confirm_and_run() {
  local desc="$1"; shift
  if [[ "$DRY_RUN" == "1" ]]; then
    printf '%s[DRY-RUN]%s %s\n' "$C_CYAN" "$C_RESET" "$desc"
    return 0
  fi
  cat <<EOF

  ${C_BOLD}これから実行するコマンド${C_RESET}
    $desc

  ${C_DIM}OMH は Hermes の上に載る運用レイヤです。Hermes 本体を置き換えません。${C_RESET}

EOF
  confirm "実行を承認しますか?" || { log_warn "承認されなかったため中止しました。"; return 1; }
  run bash -c "$desc"
}

# omh_setup_run — setup を実行 (managed skills + Hermes 登録)
#   setup は model-alias を書き換えうるため、既定では対話モードで委ねる
omh_setup_run() {
  local profile_pack="${1:-}"
  omh_installed || { log_error "OMH が未導入です。先に導入してください。"; return 1; }

  log_step "OMH setup — managed skills と Hermes 登録"

  local args=(setup)
  if [[ -n "$profile_pack" ]]; then
    args+=(--profile-pack "$profile_pack")
  fi

  if [[ "$DRY_RUN" == "1" ]]; then
    printf '%s[DRY-RUN]%s omh %s\n' "$C_CYAN" "$C_RESET" "${args[*]}"
    return 0
  fi

  cat <<EOF

  ${C_BOLD}omh setup が行う管理対象の書き込み${C_RESET}
    - ~/.omh/skills に生成 skills を配置
    - Hermes config (skills.external_dirs) にそのディレクトリを登録
    - ~/.hermes/plugins/omh に plugin bridge を配置
    - ~/.omh/routing/model-chains.json を seed
    - ~/.hermes/profiles/<name> 配下の各ホームにも登録

  ${C_YELLOW}モデル設定について${C_RESET}: setup は model-alias を変更しうる。
  既定では対話モードで実行し、変更前に承認を求める挙動に委ねる。

EOF
  confirm "omh setup を実行しますか?" || { log_warn "中止しました。"; return 1; }

  # TTY がある場合は対話モードで実行 (model-setup の承認を人に委ねる)
  run "$(omh_cmd)" "${args[@]}"
  local rc=$?
  if [[ "$rc" -ne 0 ]]; then
    log_error "omh setup が終了コード $rc で失敗しました。omh doctor で詳細を確認してください。"
    return "$rc"
  fi
  log_ok "omh setup が完了しました"
  log_dim "  setup 後の状態: $(omh_setup_status)"
  return 0
}

# update_omh — 全レイヤを更新 (managed skills / plugin / 登録も再適用される)
update_omh() {
  omh_installed || { log_error "OMH が未導入です。"; return 1; }
  log_step "OMH を更新 (omh update)"
  log_dim "  導入経路を検出し、managed skills / plugin bundle / Hermes 登録を再適用します。"
  run "$(omh_cmd)" update
  local rc=$?
  [[ "$rc" -eq 0 ]] && log_ok "OMH 更新が完了しました" || log_error "omh update が終了コード $rc で失敗しました"
  return "$rc"
}

# doctor_omh — omh doctor を実行し、JSON が得られれば要点を抽出
doctor_omh() {
  omh_installed || { log_error "OMH が未導入です。"; return 1; }
  log_step "OMH doctor"
  "$(omh_cmd)" doctor
  return $?
}
