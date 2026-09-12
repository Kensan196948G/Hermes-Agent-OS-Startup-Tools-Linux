#!/usr/bin/env bash
# ============================================================
# os-detect.sh — OS / ディストリ / WSL / 権限の判定
#   このツールは Linux native 専用。他 OS では明示的に止める。
# ============================================================

if [[ -n "${__HERMESOS_OS_DETECT_SH:-}" ]]; then
  return 0
fi
__HERMESOS_OS_DETECT_SH=1

os_kernel() { uname -s; }

os_is_linux() { [[ "$(uname -s)" == "Linux" ]]; }

os_is_wsl() {
  [[ -n "${WSL_DISTRO_NAME:-}" ]] && return 0
  grep -qiE 'microsoft|wsl' /proc/version 2>/dev/null
}

# distro_id — ubuntu / debian / fedora / arch / unknown
os_distro_id() {
  if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    local id
    id="$(grep -E '^ID=' /etc/os-release | head -1 | cut -d= -f2 | tr -d '"'"'"'')"
    printf '%s' "${id:-unknown}"
  else
    printf 'unknown'
  fi
}

os_distro_name() {
  if [[ -r /etc/os-release ]]; then
    grep -E '^PRETTY_NAME=' /etc/os-release | head -1 | cut -d= -f2 | tr -d '"'
  else
    printf '%s' "$(uname -s)"
  fi
}

os_arch() { uname -m; }

os_is_root() { [[ "$(id -u)" -eq 0 ]]; }

# package_manager — apt / dnf / pacman / unknown
os_package_manager() {
  if has_cmd apt-get; then printf 'apt'
  elif has_cmd dnf;    then printf 'dnf'
  elif has_cmd pacman; then printf 'pacman'
  else printf 'unknown'
  fi
}

# os_summary — 1行サマリ
os_summary() {
  local wsl=""
  os_is_wsl && wsl=" (WSL2)"
  printf '%s%s / %s / %s' "$(os_distro_name)" "$wsl" "$(os_arch)" "$(os_package_manager)"
}

# os_assert_supported — Linux native 以外は停止
os_assert_supported() {
  if ! os_is_linux; then
    die "このツールは Linux native 専用です (検出: $(uname -s))。WSL2 の場合は Linux 側で実行してください。"
  fi
  if os_is_wsl; then
    log_warn "WSL2 上で実行中です。Linux 経路として動作しますが、systemd 連携は制限されます。"
  fi
  return 0
}
