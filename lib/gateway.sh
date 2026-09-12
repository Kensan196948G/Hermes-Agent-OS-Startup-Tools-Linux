#!/usr/bin/env bash
# ============================================================
# gateway.sh — メッセージング Gateway (Telegram/Discord/Slack 等) の起動
#
# 事実 (upstream で確認):
#   hermes gateway        で起動
#   hermes gateway setup  で接続先を設定
#   単一の gateway プロセスが複数プラットフォームを扱う。
#   常駐させるときは tmux か systemd を使う。
# ============================================================

if [[ -n "${__HERMESOS_GATEWAY_SH:-}" ]]; then
  return 0
fi
__HERMESOS_GATEWAY_SH=1

readonly GATEWAY_SESSION="hermesos-gateway"

gateway_status() {
  printf '%sGateway%s\n' "$C_BOLD" "$C_RESET"
  if ! hermes_installed; then
    log_error "hermes が未導入です。"
    return 1
  fi
  if has_cmd tmux && tmux has-session -t "$GATEWAY_SESSION" 2>/dev/null; then
    check_pass "tmux セッション '$GATEWAY_SESSION' で稼働中"
    log_dim "  接続: tmux attach -t $GATEWAY_SESSION"
  else
    log_dim "  tmux セッション '$GATEWAY_SESSION' は存在しません。"
  fi
  log_dim "  接続先の設定状況は 'hermes gateway setup' または config.yaml で確認してください。"
  return 0
}

gateway_setup() {
  hermes_installed || { log_error "hermes が未導入です。"; return 1; }
  log_step "Gateway 接続先の設定"
  log_dim "  対話ウィザードを起動します。Telegram / Discord / Slack 等を設定できます。"
  run "$(hermes_cmd)" gateway setup
}

gateway_start_background() {
  hermes_installed || { log_error "hermes が未導入です。"; return 1; }
  has_cmd tmux || { log_error "tmux が必要です。"; return 1; }

  if tmux has-session -t "$GATEWAY_SESSION" 2>/dev/null; then
    log_warn "Gateway セッションは既に稼働中です: $GATEWAY_SESSION"
    return 1
  fi

  local logf="${HERMESOS_LOG_DIR}/gateway.log"
  mkdir -p "$HERMESOS_LOG_DIR"

  if [[ "$DRY_RUN" == "1" ]]; then
    printf '%s[DRY-RUN]%s tmux new-session -d -s %s\n' "$C_CYAN" "$C_RESET" "$GATEWAY_SESSION"
    return 0
  fi

  tmux new-session -d -s "$GATEWAY_SESSION" \
    "$(hermes_cmd) gateway 2>&1 | tee -a '$logf'" 2>/dev/null || {
    log_error "Gateway の起動に失敗しました。"
    return 1
  }
  log_ok "Gateway を起動しました: $GATEWAY_SESSION"
  log_dim "  ログ: $logf"
  return 0
}

gateway_stop() {
  if ! has_cmd tmux || ! tmux has-session -t "$GATEWAY_SESSION" 2>/dev/null; then
    log_info "Gateway は稼働していません。"
    return 0
  fi
  if confirm "Gateway セッション '$GATEWAY_SESSION' を停止しますか?"; then
    tmux kill-session -t "$GATEWAY_SESSION" && log_ok "停止しました。"
  fi
}

# gateway_guidance
gateway_guidance() {
  cat <<'GUIDE'
## Gateway — 運用の注意

- Gateway は単一プロセスで複数プラットフォームを扱う。
  二重起動すると同じメッセージに二重応答するため注意。
- 常駐させる場合は tmux (本ツール) か systemd を使う。
- 接続先の資格情報は config.yaml / 認証情報に保存される。
  権限を 600 に保つこと。
- 「設定した」と「動いている」は別である。
  起動後に実際にメッセージを送って OBSERVED にするまで完了としない。
GUIDE
}
