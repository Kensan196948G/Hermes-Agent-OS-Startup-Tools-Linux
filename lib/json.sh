#!/usr/bin/env bash
# ============================================================
# json.sh — JSON 設定の読み出しヘルパ (jq ラッパ)
#   jq が無い場合は安全側に倒し、呼び出し側が既定値で動けるようにする。
# ============================================================

if [[ -n "${__HERMESOS_JSON_SH:-}" ]]; then
  return 0
fi
__HERMESOS_JSON_SH=1

# jq 利用可否
json_available() { has_cmd jq; }

# json_get <file> <jq-filter> [default]
#   例: json_get config/config.json '.runtime.hermes_home' "$HOME/.hermes"
json_get() {
  local file="$1" filter="$2" default="${3:-}"
  if [[ ! -f "$file" ]]; then
    printf '%s' "$default"
    return 0
  fi
  if ! json_available; then
    printf '%s' "$default"
    return 0
  fi
  local out
  out="$(jq -r "$filter // empty" "$file" 2>/dev/null || true)"
  if [[ -z "$out" || "$out" == "null" ]]; then
    printf '%s' "$default"
  else
    printf '%s' "$out"
  fi
}

# json_get_bool <file> <filter> [default:false]
json_get_bool() {
  local file="$1" filter="$2" default="${3:-false}" out
  out="$(json_get "$file" "$filter" "$default")"
  case "$out" in
    true|True|TRUE|1|yes|on) printf 'true' ;;
    *) printf 'false' ;;
  esac
}

# json_valid <file> — JSON として妥当か
json_valid() {
  local file="$1"
  [[ -f "$file" ]] || return 1
  json_available || return 1
  jq empty "$file" >/dev/null 2>&1
}
