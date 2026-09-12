#!/usr/bin/env bash
# ============================================================
# hermes-install.sh — Hermes 本体の導入 / 更新
#
# 事実 (upstream で確認):
#   公式ワンライナー: curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash
#   完了後: source ~/.bashrc  →  hermes  で対話開始
#   per-user 配置: code ~/.hermes/hermes-agent/ , binary ~/.local/bin/hermes
#
# 方針 (安全側):
#   * 既定は「検査のみ」。導入は明示選択 + 確認時のみ実行する
#   * installer は上流スクリプトである。内容を検証せず無確認で流さない
#   * 更新は Hermes 自身の updater (hermes update) に委ねる
# ============================================================

if [[ -n "${__HERMESOS_HERMES_INSTALL_SH:-}" ]]; then
  return 0
fi
__HERMESOS_HERMES_INSTALL_SH=1

readonly HERMES_INSTALL_URL="https://hermes-agent.nousresearch.com/install.sh"

# hermes_install_status — 現在の導入状態を1行で
hermes_install_status() {
  if hermes_installed; then
    local v; v="$(hermes_version)"
    printf 'installed (%s) at %s' "${v:-version unknown}" "$(command -v hermes 2>/dev/null || printf '%s' "$HERMES_BIN")"
  else
    printf 'NOT installed'
  fi
}

# install_preflight — installer を流す前の検査
install_preflight() {
  log_step "Hermes 導入前チェック"
  local ok=0

  if ! has_cmd curl; then
    check_fail "curl が無い (installer の取得に必須)"
    ok=1
  else
    check_pass "curl $(curl --version 2>/dev/null | head -1 | awk '{print $2}')"
  fi

  if ! has_cmd bash; then
    check_fail "bash が無い"
    ok=1
  else
    check_pass "bash ${BASH_VERSION}"
  fi

  # ネットワーク到達性 — 取得できなければ導入は失敗する
  if has_cmd curl; then
    if curl -fsSL --max-time 20 -o /dev/null "$HERMES_INSTALL_URL" 2>/dev/null; then
      check_pass "installer に到達可能 ($HERMES_INSTALL_URL)"
    else
      check_fail "installer に到達できない。ネットワーク/DNS/プロキシを確認"
      ok=1
    fi
  fi

  # ディスク空き (installer は Python/Node/ffmpeg 等を同梱するため数 GB 使う)
  local avail_kb avail_gb
  avail_kb="$(df -Pk "$HOME" 2>/dev/null | awk 'NR==2{print $4}')"
  if [[ -n "${avail_kb:-}" ]]; then
    avail_gb=$((avail_kb / 1024 / 1024))
    if [[ "$avail_gb" -lt 3 ]]; then
      check_warn "HOME の空きが ${avail_gb}GB です。installer は依存を同梱するため 3GB 以上を推奨"
    else
      check_pass "HOME 空き ${avail_gb}GB"
    fi
  fi

  # PATH — ~/.local/bin が通っていないと hermes が見えない
  case ":$PATH:" in
    *":$HOME/.local/bin:"*) check_pass "PATH に ~/.local/bin が含まれる" ;;
    *) check_warn "PATH に ~/.local/bin が無い。hermes 導入後に \`export PATH=\"\$HOME/.local/bin:\$PATH\"\` が必要" ;;
  esac

  return "$ok"
}

# install_hermes_yolo — 実際に installer を流す (呼び出し側で確認済みであること)
install_hermes_yolo() {
  log_step "Hermes 本体を導入"

  # dry-run では「実行した」と報告してはならない (evidence boundary)。
  if [[ "$DRY_RUN" == "1" ]]; then
    printf '%s[DRY-RUN]%s bash -c "curl -fsSL %s | bash"\n' \
      "$C_CYAN" "$C_RESET" "$HERMES_INSTALL_URL"
    log_dim "  未実行です。実際に導入するには HERMESOS_DRY_RUN を外してください。"
    return 0
  fi

  log_warn "上流 installer を実行します: $HERMES_INSTALL_URL"
  log_dim "  この installer は uv / Python 3.11 / Node.js / ripgrep / ffmpeg 等を導入します。"

  if ! bash -c "curl -fsSL '$HERMES_INSTALL_URL' | bash"; then
    log_error "installer が失敗しました。上流の出力を確認してください。"
    return 1
  fi

  log_ok "installer の実行が完了しました"
  log_dim "  shell を再読込してください: source ~/.bashrc"
  log_dim "  反映の確認: hermes --version"
  return 0
}

# install_hermes — 確認つき導入フロー
install_hermes() {
  if hermes_installed && [[ "${HERMESOS_FORCE:-0}" != "1" ]]; then
    log_ok "Hermes は既に導入済みです: $(hermes_install_status)"
    log_dim "  再導入する場合は HERMESOS_FORCE=1 を指定してください"
    return 0
  fi

  if ! install_preflight; then
    die "導入前チェックに失敗しました。上記の FAIL を解消してから再実行してください。"
  fi

  if [[ "$DRY_RUN" == "1" ]]; then
    log_dim "[DRY-RUN] install_hermes_yolo を実行します"
    install_hermes_yolo
    return 0
  fi

  cat <<EOF

  ${C_BOLD}これから実行するコマンド${C_RESET}
    curl -fsSL $HERMES_INSTALL_URL | bash

  ${C_YELLOW}注意${C_RESET}: 上流の installer スクリプトです。次の点を理解した上で承認してください。
    - 依存 (uv / Python 3.11 / Node.js / ripgrep / ffmpeg) を自動導入します
    - ~/.hermes/hermes-agent/ にコードを clone します
    - ~/.local/bin/hermes にコマンドを配置します
    - shell 設定 (~/.bashrc 等) を書き換える場合があります

  ${C_DIM}内容を事前に確認する場合:  curl -fsSL $HERMES_INSTALL_URL | less${C_RESET}

EOF
  if ! confirm "上記を理解し、installer の実行を承認しますか?"; then
    log_warn "利用者が承認しなかったため導入を中止しました。"
    return 1
  fi

  install_hermes_yolo
}

# update_hermes — Hermes 自身の updater を使う
update_hermes() {
  if ! hermes_installed; then
    log_error "Hermes が未導入です。先に導入してください。"
    return 1
  fi
  log_step "Hermes 本体を更新 (hermes update)"
  run "$(hermes_cmd)" update
  log_ok "更新コマンドが完了しました"
  log_dim "  新しいバージョン: $(hermes_version)"
}

# hermes_path_hint — PATH が通っていない場合の対処を表示
hermes_path_hint() {
  if [[ -x "$HERMES_BIN" ]] && ! has_cmd hermes; then
    log_warn "hermes は $HERMES_BIN にありますが PATH に含まれていません。"
    log_dim "  対処: export PATH=\"\$HOME/.local/bin:\$PATH\""
    log_dim "        echo 'export PATH=\"\$HOME/.local/bin:\$PATH\"' >> ~/.bashrc"
    return 1
  fi
  return 0
}
