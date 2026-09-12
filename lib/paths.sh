#!/usr/bin/env bash
# ============================================================
# paths.sh — Hermes / OMH の実パス解決
#
# すべて upstream で確認した事実に基づく (推測しない):
#   Hermes per-user install:
#     code   : ~/.hermes/hermes-agent/
#     binary : ~/.local/bin/hermes
#     data   : ~/.hermes/            (HERMES_HOME で上書き可)
#   OMH setup が行う managed write:
#     skills : ~/.omh/skills          → hermes config skills.external_dirs
#     plugin : ~/.hermes/plugins/omh
#     routing: ~/.omh/routing/model-chains.json
#   profile: ~/.hermes/profiles/<name>/   (bot/profile 単位のホーム)
# ============================================================

if [[ -n "${__HERMESOS_PATHS_SH:-}" ]]; then
  return 0
fi
__HERMESOS_PATHS_SH=1

HERMES_HOME="$(resolve_hermes_home)"
OMH_HOME="$(resolve_omh_home)"

readonly HERMES_CONFIG="${HERMES_HOME}/config.yaml"
readonly HERMES_CODE_DIR="${HERMES_HOME}/hermes-agent"
readonly HERMES_PLUGINS_DIR="${HERMES_HOME}/plugins"
readonly HERMES_OMH_PLUGIN_DIR="${HERMES_HOME}/plugins/omh"
readonly HERMES_PROFILES_DIR="${HERMES_HOME}/profiles"
readonly HERMES_SKILLS_DIR="${HERMES_HOME}/skills"
readonly HERMES_SESSIONS_DIR="${HERMES_HOME}/sessions"
# 記憶ディレクトリは複数形 "memories" が正しい (hermes doctor で実測確認)。
# MEMORY.md / USER.md がエージェントの記憶本体である。
readonly HERMES_MEMORY_DIR="${HERMES_HOME}/memories"
readonly HERMES_STATE_DB="${HERMES_HOME}/state.db"
readonly HERMES_BIN="${HOME}/.local/bin/hermes"

readonly OMH_SKILLS_DIR="${OMH_HOME}/skills"
readonly OMH_ROUTING_DIR="${OMH_HOME}/routing"
readonly OMH_MODEL_CHAINS="${OMH_HOME}/routing/model-chains.json"
readonly OMH_BIN="${HOME}/.local/bin/omh"

# hermes_cmd — PATH 優先、無ければ既知の絶対パス
hermes_cmd() {
  if has_cmd hermes; then
    printf 'hermes'
  elif [[ -x "$HERMES_BIN" ]]; then
    printf '%s' "$HERMES_BIN"
  else
    printf 'hermes'   # 呼び出し側で存在確認する
  fi
}

omh_cmd() {
  if has_cmd omh; then
    printf 'omh'
  elif [[ -x "$OMH_BIN" ]]; then
    printf '%s' "$OMH_BIN"
  else
    printf 'omh'
  fi
}

hermes_installed() { has_cmd hermes || [[ -x "$HERMES_BIN" ]]; }
omh_installed()    { has_cmd omh    || [[ -x "$OMH_BIN" ]]; }

# hermes_version — 取得できなければ空
hermes_version() {
  hermes_installed || { printf ''; return 0; }
  "$(hermes_cmd)" --version 2>/dev/null | head -1 | tr -d '\r' || printf ''
}

omh_version() {
  omh_installed || { printf ''; return 0; }
  "$(omh_cmd)" --version 2>/dev/null | head -1 | tr -d '\r' || printf ''
}

# plugin_registered — Hermes config が OMH プラグインを登録しているか
plugin_registered() {
  [[ -d "$HERMES_OMH_PLUGIN_DIR" ]]
}

# skills_dir_registered — config.yaml の skills.external_dirs に ~/.omh/skills があるか
skills_dir_registered() {
  [[ -f "$HERMES_CONFIG" ]] || return 1
  grep -qF "$OMH_SKILLS_DIR" "$HERMES_CONFIG" 2>/dev/null
}
