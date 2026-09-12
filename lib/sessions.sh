#!/usr/bin/env bash
# ============================================================
# sessions.sh — Hermes 実行セッションの起動 / 監視 / 終了
#
# 起動経路:
#   foreground : カレント端末で直接 hermes を実行 (tmux 不使用)
#   background : tmux セッション内で hermes を実行し、デタッチで継続
#
# 命名規則: <prefix>-<project>   (既定 prefix = hermesos)
# セッション上限: HERMESOS_FOREGROUND_MINUTES (0 = 無制限)
# ============================================================

if [[ -n "${__HERMESOS_SESSIONS_SH:-}" ]]; then
  return 0
fi
__HERMESOS_SESSIONS_SH=1

SESSION_PREFIX="${HERMESOS_TMUX_PREFIX:-hermesos}"

# session_name <project>
session_name() { printf '%s-%s' "$SESSION_PREFIX" "$1"; }

# sessions_list — hermesos-* セッション名を1行ずつ
sessions_list() {
  has_cmd tmux || return 0
  tmux list-sessions -F '#{session_name}' 2>/dev/null | grep -E "^${SESSION_PREFIX}-" || true
}

sessions_count() {
  local n; n="$(sessions_list | grep -c . || true)"
  printf '%s' "${n:-0}"
}

# session_exists <name>
session_exists() {
  has_cmd tmux || return 1
  tmux has-session -t "$1" 2>/dev/null
}

# session_meta <name> — 開始時刻と経過を返す
session_started_epoch() {
  has_cmd tmux || return 1
  tmux display-message -p -t "$1" '#{session_created}' 2>/dev/null || return 1
}

# _fmt_duration <seconds>
_fmt_duration() {
  local s="$1"
  if [[ "$s" -lt 0 ]]; then printf '-'; return; fi
  printf '%02d:%02d:%02d' $((s / 3600)) $(((s % 3600) / 60)) $((s % 60))
}

# sessions_status — 一覧表示 (経過 / 残り)
sessions_status() {
  if ! has_cmd tmux; then
    log_warn "tmux がありません。セッション監視は利用できません。"
    return 1
  fi

  local list; list="$(sessions_list)"
  if [[ -z "$list" ]]; then
    log_info "実行中の ${SESSION_PREFIX}-* セッションはありません。"
    return 0
  fi

  printf '%s%-24s %-10s %-10s %-10s %s%s\n' \
    "$C_BOLD" "SESSION" "ELAPSED" "LIMIT" "REMAIN" "STATUS" "$C_RESET"
  printf '%s%s%s\n' "$C_DIM" "$(printf '%.0s─' {1..78})" "$C_RESET"

  local now; now="$(date +%s)"
  local s created elapsed limit_s remain status
  while IFS= read -r s; do
    [[ -z "$s" ]] && continue
    created="$(session_started_epoch "$s" || printf '%s' "$now")"
    elapsed=$((now - created))

    if [[ "${HERMESOS_FOREGROUND_MINUTES:-0}" -gt 0 ]]; then
      limit_s=$((HERMESOS_FOREGROUND_MINUTES * 60))
      remain=$((limit_s - elapsed))
      status="running"
      [[ "$remain" -le 0 ]] && status="OVER LIMIT"
    else
      limit_s=0; remain=0; status="running (unlimited)"
    fi

    printf '%-24s %-10s %-10s %-10s %s\n' \
      "$s" "$(_fmt_duration "$elapsed")" \
      "$([[ "$limit_s" -eq 0 ]] && printf 'none' || _fmt_duration "$limit_s")" \
      "$([[ "$limit_s" -eq 0 ]] && printf '-' || _fmt_duration "$remain")" \
      "$status"
  done <<< "$list"

  printf '\n%s接続: tmux attach -t <SESSION>   (Ctrl-b d でデタッチ = バックグラウンド継続)%s\n' "$C_DIM" "$C_RESET"
  return 0
}

# session_start_background <project> [workdir] [extra hermes args...]
session_start_background() {
  local project="$1"; shift
  local workdir="${1:-$PWD}"; shift || true
  local name; name="$(session_name "$project")"

  if ! has_cmd tmux; then
    log_error "バックグラウンド起動には tmux が必要です。"
    _session_tmux_hint
    return 1
  fi
  if session_exists "$name"; then
    log_warn "セッション '$name' は既に存在します。"
    log_dim "  接続: tmux attach -t $name"
    return 1
  fi
  if ! hermes_installed; then
    log_error "hermes が未導入です。先に導入してください。"
    return 1
  fi

  local hcmd; hcmd="$(hermes_cmd)"
  log_step "バックグラウンド起動: $name"
  log_dim "  workdir: $workdir"

  # tmux new-session は shell-command を単一文字列として自身のシェルへ渡すため、
  # 各引数を printf %q で個別にクォートしてから連結する
  # (未クォート連結は将来 extra args が配線された際のコマンドインジェクションになる)。
  local shell_cmd; shell_cmd="$(printf '%q ' "$hcmd" "$@")"

  if [[ "$DRY_RUN" == "1" ]]; then
    printf '%s[DRY-RUN]%s tmux new-session -d -s %s -c %s %s\n' \
      "$C_CYAN" "$C_RESET" "$name" "$workdir" "$shell_cmd"
    return 0
  fi

  # ログを残す: tmux の出力を log ディレクトリへ
  "$(hermes_cmd)" >/dev/null 2>&1 || true   # 存在確認を兼ねる (失敗は無視)
  tmux new-session -d -s "$name" -c "$workdir" "$shell_cmd" 2>/dev/null || {
    log_error "tmux セッションの作成に失敗しました。"
    return 1
  }
  log_ok "セッションを開始しました: $name"
  log_dim "  接続: tmux attach -t $name"
  log_dim "  一覧: bash bin/sessions.sh status"
  return 0
}

# session_start_foreground <workdir> [extra hermes args...]
session_start_foreground() {
  local workdir="$1"; shift || true

  if ! hermes_installed; then
    log_error "hermes が未導入です。先に導入してください。"
    return 1
  fi
  log_step "フォアグラウンド起動 (− minutes: ${HERMESOS_FOREGROUND_MINUTES}, 0=無制限)"
  log_dim "  workdir: $workdir"

  if [[ "$DRY_RUN" == "1" ]]; then
    printf '%s[DRY-RUN]%s cd %s && %s %s\n' "$C_CYAN" "$C_RESET" "$workdir" "$(hermes_cmd)" "$*"
    return 0
  fi

  cd "$workdir" || { log_error "workdir に移動できません: $workdir"; return 1; }

  if [[ "${HERMESOS_FOREGROUND_MINUTES:-0}" -gt 0 ]]; then
    log_warn "上限 ${HERMESOS_FOREGROUND_MINUTES} 分を適用します (timeout 使用)。"
    timeout --signal=INT "$((HERMESOS_FOREGROUND_MINUTES * 60))" "$(hermes_cmd)" "$@"
    local rc=$?
    [[ "$rc" -eq 124 ]] && log_warn "上限時間に達したため終了しました。"
    return "$rc"
  fi

  "$(hermes_cmd)" "$@"
}

# session_attach <name>
session_attach() {
  local name="$1"
  session_exists "$name" || { log_error "セッションがありません: $name"; return 1; }
  exec tmux attach -t "$name"
}

# session_kill <name>
session_kill() {
  local name="$1"
  session_exists "$name" || { log_error "セッションがありません: $name"; return 1; }
  if confirm "セッション '$name' を終了しますか?"; then
    tmux kill-session -t "$name" && log_ok "終了しました: $name"
  else
    log_dim "中止しました。"
  fi
}

# session_kill_all
session_kill_all() {
  local list; list="$(sessions_list)"
  [[ -z "$list" ]] && { log_info "終了対象のセッションはありません。"; return 0; }
  printf '対象:\n%s\n' "$list"
  if confirm "上記すべてのセッションを終了しますか?"; then
    local s
    while IFS= read -r s; do
      [[ -n "$s" ]] && tmux kill-session -t "$s" 2>/dev/null && log_ok "終了: $s"
    done <<< "$list"
  fi
}

_session_tmux_hint() {
  case "$(os_package_manager)" in
    apt)    log_dim "  対処例: sudo apt-get install -y tmux" ;;
    dnf)    log_dim "  対処例: sudo dnf install -y tmux" ;;
    pacman) log_dim "  対処例: sudo pacman -S tmux" ;;
    *)      log_dim "  対処: tmux を導入してください" ;;
  esac
}
