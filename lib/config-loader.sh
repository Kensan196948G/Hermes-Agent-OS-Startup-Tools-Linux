#!/usr/bin/env bash
# ============================================================
# config-loader.sh — config/config.json の読込と既定値の適用
#
# 優先順位:
#   1. 環境変数 (HERMESOS_*)
#   2. config/config.json
#   3. 既定値 (このファイル)
#
# config/config.json が無い場合は config.json.template では動かさず、
# 既定値で動く (「設定が無いから落ちる」を避ける)。
# ============================================================

if [[ -n "${__HERMESOS_CONFIG_LOADER_SH:-}" ]]; then
  return 0
fi
__HERMESOS_CONFIG_LOADER_SH=1

HERMESOS_CONFIG_FILE="${HERMESOS_CONFIG_FILE:-${HERMESOS_ROOT}/config/config.json}"

# --- 既定値 ---
: "${HERMESOS_HERMES_HOME:=${HOME}/.hermes}"
: "${HERMESOS_OMH_HOME:=${HOME}/.omh}"
: "${HERMESOS_INSTALL_METHOD:=installer}"      # installer | npm | bun | brew
: "${HERMESOS_FOREGROUND_MINUTES:=0}"          # 0 = 無制限
: "${HERMESOS_TMUX_PREFIX:=hermesos}"
: "${HERMESOS_LOG_DIR:=${HERMESOS_ROOT}/logs}"
: "${HERMESOS_NOTIFY_ON_ERROR:=true}"

# JSON から読んだパスはシェル展開されないため、先頭の ~ を明示的に展開する。
# (例: "~/.hermes" をそのまま使うと存在しないパスになる)
# ${p#\~/} の ~ はパターンであり、クォート内でも展開されない。
# エスケープしないとリテラルの "~" が残り $HOME/~/.hermes になる。
# SC2088 はこのパターン文脈では誤検知のため関数単位で無効化する。
# shellcheck disable=SC2088
expand_path() {
  local p="$1"
  case "$p" in
    "~")   printf '%s' "$HOME" ;;
    "~/"*) printf '%s/%s' "$HOME" "${p#\~/}" ;;
    *)     printf '%s' "$p" ;;
  esac
}

config_load() {
  local f="$HERMESOS_CONFIG_FILE"
  if [[ ! -f "$f" ]]; then
    log_dim "  config.json が見つからないため既定値で動作します: $f"
    log_dim "  ひな形: cp config/config.json.template config/config.json"
    return 0
  fi
  if ! json_valid "$f"; then
    log_warn "config.json が不正な JSON です。既定値で続行します: $f"
    return 1
  fi

  # 環境変数が既に設定されていればそちらを優先する
  if [[ -z "${HERMES_HOME:-}" ]]; then
    HERMES_HOME="$(expand_path "$(json_get "$f" '.hermes.hermes_home' "${HOME}/.hermes")")"
  fi
  if [[ -z "${OMH_HOME:-}" ]]; then
    OMH_HOME="$(expand_path "$(json_get "$f" '.hermes.omh_home' "${HOME}/.omh")")"
  fi

  HERMESOS_INSTALL_METHOD="$(json_get "$f" '.install.method' "$HERMESOS_INSTALL_METHOD")"
  HERMESOS_FOREGROUND_MINUTES="$(json_get "$f" '.runtime.foregroundMinutes' "$HERMESOS_FOREGROUND_MINUTES")"
  HERMESOS_TMUX_PREFIX="$(json_get "$f" '.runtime.tmuxPrefix' "$HERMESOS_TMUX_PREFIX")"

  export HERMES_HOME OMH_HOME HERMESOS_INSTALL_METHOD
  export HERMESOS_FOREGROUND_MINUTES HERMESOS_TMUX_PREFIX
  return 0
}

# 解決済みの値を使って paths.sh の readonly を再計算する必要があるため、
# config_load は paths.sh より前に呼ぶこと。
config_show() {
  printf '%s設定の実効値%s\n' "$C_BOLD" "$C_RESET"
  printf '  %-28s %s\n' "config file"        "$HERMESOS_CONFIG_FILE"
  printf '  %-28s %s\n' "HERMES_HOME"        "$HERMES_HOME"
  printf '  %-28s %s\n' "OMH_HOME"           "$OMH_HOME"
  printf '  %-28s %s\n' "install method"     "$HERMESOS_INSTALL_METHOD"
  printf '  %-28s %s\n' "foreground minutes" "$HERMESOS_FOREGROUND_MINUTES"
  printf '  %-28s %s\n' "tmux prefix"        "$HERMESOS_TMUX_PREFIX"
  printf '  %-28s %s\n' "log dir"            "$HERMESOS_LOG_DIR"
  printf '  %-28s %s\n' "dry run"            "$DRY_RUN"
}
