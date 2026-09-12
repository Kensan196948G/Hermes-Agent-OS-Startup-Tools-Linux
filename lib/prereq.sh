#!/usr/bin/env bash
# ============================================================
# prereq.sh — 前提コマンドの検査と欠落の提示
#
# 事実に基づく要件 (upstream で確認済み):
#   Hermes 公式 installer は uv / Python 3.11 / Node.js / ripgrep / ffmpeg
#   等を「自分で導入する」。したがってこれらは *事前必須ではない*。
#   必須なのは installer を起動する curl と bash のみ。
#   ただし導入後に hermes が動くには PATH と shell 再読込が要る。
# ============================================================

if [[ -n "${__HERMESOS_PREREQ_SH:-}" ]]; then
  return 0
fi
__HERMESOS_PREREQ_SH=1

readonly PREREQ_BOOTSTRAP=(bash curl)
readonly PREREQ_RUNTIME=(git)
readonly PREREQ_OPTIONAL=(jq tmux rg ffmpeg uv node python3 shellcheck bats)

# prereq_report — 区分ごとに存在を報告。欠落の致命度を明示する
prereq_report() {
  local missing_bootstrap=() missing_runtime=() missing_optional=()

  log_step "前提コマンド検査"
  printf '  %sインストーラ起動に必須%s\n' "$C_BOLD" "$C_RESET"
  local c
  for c in "${PREREQ_BOOTSTRAP[@]}"; do
    if has_cmd "$c"; then
      check_pass "$c"
    else
      check_fail "$c (必須)"
      missing_bootstrap+=("$c")
    fi
  done

  printf '\n  %s実行時にあると良いもの%s\n' "$C_BOLD" "$C_RESET"
  for c in "${PREREQ_RUNTIME[@]}"; do
    if has_cmd "$c"; then
      check_pass "$c"
    else
      check_warn "$c (推奨)"
      missing_runtime+=("$c")
    fi
  done

  printf '\n  %sHermes が同梱または導入するもの / 任意%s\n' "$C_BOLD" "$C_RESET"
  for c in "${PREREQ_OPTIONAL[@]}"; do
    if has_cmd "$c"; then
      check_pass "$c"
    else
      check_skip "$c (任意 — installer が導入、または本ツールの一部機能で使用)"
      missing_optional+=("$c")
    fi
  done

  printf '\n'
  if [[ "${#missing_bootstrap[@]}" -gt 0 ]]; then
    log_error "必須コマンドが欠落: ${missing_bootstrap[*]}"
    _prereq_install_hint "${missing_bootstrap[@]}"
    return 1
  fi

  if [[ "${#missing_runtime[@]}" -gt 0 ]]; then
    log_warn "推奨コマンドが欠落: ${missing_runtime[*]}"
    _prereq_install_hint "${missing_runtime[@]}"
  fi

  # jq は本ツールの config 読込に使うため、無い場合は明示
  if ! has_cmd jq; then
    log_warn "jq が無いため config.json の値は既定値で動作します。"
  fi

  log_ok "前提検査を通過しました"
  return 0
}

# _prereq_install_hint <cmd...> — distro に応じた導入例を出す
_prereq_install_hint() {
  local pm; pm="$(os_package_manager)"
  local pkgs=() c
  for c in "$@"; do
    case "$c" in
      rg) pkgs+=("ripgrep") ;;
      node) pkgs+=("nodejs") ;;
      *) pkgs+=("$c") ;;
    esac
  done
  case "$pm" in
    apt)    log_dim "  対処例: sudo apt-get update && sudo apt-get install -y ${pkgs[*]}" ;;
    dnf)    log_dim "  対処例: sudo dnf install -y ${pkgs[*]}" ;;
    pacman) log_dim "  対処例: sudo pacman -S --needed ${pkgs[*]}" ;;
    *)      log_dim "  対処: お使いのパッケージマネージャで ${pkgs[*]} を導入してください" ;;
  esac
}

# prereq_check_single <cmd> — 単体確認 (戻り値のみ)
prereq_check_single() { has_cmd "$1"; }
