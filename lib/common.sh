#!/usr/bin/env bash
# ============================================================
# common.sh — 全スクリプト共通の基盤関数
#   - 色 / ログ / エラー
#   - ルート解決 / XDG・Hermes ホーム解決
#   - 安全な実行ヘルパ (confirm, require_cmd, run_or_die)
#
# 方針:
#   * 破壊的操作は必ず confirm を通す
#   * 未検証の断定をしない: 失敗は握りつぶさず可視化する
# ============================================================

# --- 二重 source ガード ---
if [[ -n "${__HERMESOS_COMMON_SH:-}" ]]; then
  return 0
fi
__HERMESOS_COMMON_SH=1

set -euo pipefail

# --- ルート解決 ---
# lib/common.sh から見たプロジェクトルート
HERMESOS_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HERMESOS_ROOT="$(cd "${HERMESOS_LIB_DIR}/.." && pwd)"
export HERMESOS_LIB_DIR HERMESOS_ROOT

# --- バージョン / 名称 ---
readonly HERMESOS_NAME="HermesAgentOS-StartUpTools"
readonly HERMESOS_VERSION="1.0.0-linux"

# --- 色 (TTY でないときは無効化) ---
if [[ -t 1 ]] && [[ "${NO_COLOR:-}" == "" ]]; then
  readonly C_RESET=$'\033[0m'
  readonly C_BOLD=$'\033[1m'
  readonly C_DIM=$'\033[2m'
  readonly C_RED=$'\033[31m'
  readonly C_GREEN=$'\033[32m'
  readonly C_YELLOW=$'\033[33m'
  readonly C_BLUE=$'\033[34m'
  readonly C_MAGENTA=$'\033[35m'
  readonly C_CYAN=$'\033[36m'
else
  readonly C_RESET="" C_BOLD="" C_DIM="" C_RED="" C_GREEN=""
  readonly C_YELLOW="" C_BLUE="" C_MAGENTA="" C_CYAN=""
fi
export C_RESET C_BOLD C_DIM C_RED C_GREEN C_YELLOW C_BLUE C_MAGENTA C_CYAN

# --- ログ出力 (すべて stderr ではなく stdout、パイプ可能) ---
log_info()  { printf '%s[INFO]%s  %s\n'  "$C_BLUE"   "$C_RESET" "$*"; }
log_ok()    { printf '%s[ OK ]%s  %s\n'  "$C_GREEN"  "$C_RESET" "$*"; }
log_warn()  { printf '%s[WARN]%s  %s\n'  "$C_YELLOW" "$C_RESET" "$*" >&2; }
log_error() { printf '%s[FAIL]%s  %s\n'  "$C_RED"    "$C_RESET" "$*" >&2; }
log_step()  { printf '\n%s==>%s %s%s%s\n' "$C_MAGENTA" "$C_RESET" "$C_BOLD" "$*" "$C_RESET"; }
log_dim()   { printf '%s%s%s\n' "$C_DIM" "$*" "$C_RESET"; }

# die <message> [exit_code] — 即時中断
die() {
  log_error "$1"
  exit "${2:-1}"
}

# --- コマンド存在確認 ---
has_cmd() { command -v "$1" >/dev/null 2>&1; }

# require_cmd <cmd> [hint]
require_cmd() {
  local cmd="$1" hint="${2:-}"
  if ! has_cmd "$cmd"; then
    log_error "必須コマンドが見つかりません: $cmd"
    [[ -n "$hint" ]] && log_dim "  対処: $hint"
    return 1
  fi
  return 0
}

# --- Hermes / OMH ホーム解決 ---
# HERMES_HOME が明示されていればそれに従う (Hermes 本体と同じ規約)
resolve_hermes_home() {
  printf '%s' "${HERMES_HOME:-$HOME/.hermes}"
}

# OMH ホーム解決 (OMH_HOME 明示 > ~/.omh)
resolve_omh_home() {
  printf '%s' "${OMH_HOME:-$HOME/.omh}"
}

# --- 安全な確認 ---
# confirm <prompt> — 非対話 (HERMESOS_ASSUME_YES=1) なら常に yes
confirm() {
  local prompt="$1" reply
  if [[ "${HERMESOS_ASSUME_YES:-0}" == "1" ]]; then
    log_dim "  (--yes 指定のため自動承認) ${prompt}"
    return 0
  fi
  if [[ ! -t 0 ]]; then
    log_warn "非対話環境のため確認をスキップできません: ${prompt}"
    return 1
  fi
  printf '%s%s%s [y/N]: ' "$C_YELLOW" "$prompt" "$C_RESET" >&2
  read -r reply || return 1
  [[ "$reply" =~ ^[Yy]([Ee][Ss])?$ ]]
}

# --- ドライラン対応 ---
# HERMESOS_DRY_RUN=1 のとき、実行せずコマンドを表示する
DRY_RUN="${HERMESOS_DRY_RUN:-0}"
run() {
  if [[ "$DRY_RUN" == "1" ]]; then
    printf '%s[DRY-RUN]%s %s\n' "$C_CYAN" "$C_RESET" "$*"
    return 0
  fi
  "$@"
}

# run_show — dry-run でも実行して出力を見たい診断系に使う
run_show() { "$@"; }

# --- 集計カウンタ (doctor などで使用) ---
CHECKS_PASS=0
CHECKS_WARN=0
CHECKS_FAIL=0
CHECKS_SKIP=0

check_pass() { CHECKS_PASS=$((CHECKS_PASS + 1)); printf '  %s✓%s %s\n' "$C_GREEN" "$C_RESET" "$*"; }
check_warn() { CHECKS_WARN=$((CHECKS_WARN + 1)); printf '  %s!%s %s\n' "$C_YELLOW" "$C_RESET" "$*"; }
check_fail() { CHECKS_FAIL=$((CHECKS_FAIL + 1)); printf '  %s✗%s %s\n' "$C_RED" "$C_RESET" "$*"; }
check_skip() { CHECKS_SKIP=$((CHECKS_SKIP + 1)); printf '  %s-%s %s\n' "$C_DIM" "$C_RESET" "$*"; }
# check_dim_ok — 情報提供のみ。合否に数えない (PASS と偽らない)
check_dim_ok() { printf '  %s·%s %s\n' "$C_DIM" "$C_RESET" "$*"; }

# --- バナー ---
print_banner() {
  printf '%s%s%s\n' "$C_CYAN" "  ⚚  HermesAgentOS StartUpTools  —  HermesAgentCLI + Oh My Hermes (OMH)" "$C_RESET"
  printf '%s     Linux native / v%s / root: %s%s\n\n' "$C_DIM" "$HERMESOS_VERSION" "$HERMESOS_ROOT" "$C_RESET"
}
