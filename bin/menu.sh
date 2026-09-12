#!/usr/bin/env bash
# ============================================================
# menu.sh — 運用管理メニュー (対話) / CLI エントリ (非対話)
#
#   ./start.sh                対話メニュー
#   ./start.sh --doctor       統合診断
#   ./start.sh --list-skills  スキル一覧
#   ./start.sh --help         ヘルプ
#
# 設計原則:
#   破壊的操作 (導入・更新・復元・停止) は必ず確認を挟む。
#   本ツール自身は Hermes の記憶や設定を無断で書き換えない。
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/bootstrap.sh
source "${SCRIPT_DIR}/../lib/bootstrap.sh"

# ------------------------------------------------------------
# ヘルプ
# ------------------------------------------------------------
usage() {
  cat <<EOF
${C_BOLD}${HERMESOS_NAME}${C_RESET} v${HERMESOS_VERSION} — HermesAgentCLI + Oh My Hermes (OMH)

${C_BOLD}使い方${C_RESET}
  ./start.sh                    対話メニューを開く
  ./start.sh <command> [args]   非対話で1コマンド実行

${C_BOLD}コマンド${C_RESET}
  doctor                統合診断 (PASS/WARN/FAIL/SKIP と次の一手)
  doctor --quick        上流 omh doctor を呼ばずに高速診断
  prereq                前提コマンド検査
  config                実効設定の表示
  install hermes        Hermes 本体を導入 (要確認)
  install omh [method]  OMH を導入 (installer|npm|bun|brew)
  setup omh             omh setup を実行 (managed skills + Hermes 登録)
  update [hermes|omh]   更新
  start [project] [args]        Hermes をフォアグラウンド起動
  bg <project> [workdir]        Hermes を tmux でバックグラウンド起動
  sessions [status|kill]        セッション監視 / 終了
  attach <session>              tmux セッションへ接続
  skills [summary|list|search <p>|family <id>]   スキルカタログ
  workflows                     ワークフロー集と役割
  routing [status|validate|seed|readiness|guidance]
  memory [status|backup|list|guidance]
  profiles [status|sync|inspect <name>]
  gateway [status|setup|start|stop]
  evidence [rules|write|check]  Evidence boundaries 規約
  loop [list|new|iterate|show|close|guidance]
  emit-rules                    evidence / loop 規約を HERMES_HOME に書き出す
  help                          このヘルプ

${C_BOLD}環境変数${C_RESET}
  HERMES_HOME                  Hermes データ領域 (既定 ~/.hermes)
  OMH_HOME                     OMH データ領域 (既定 ~/.omh)
  HERMESOS_DRY_RUN=1           実行せずコマンドを表示
  HERMESOS_ASSUME_YES=1        確認を自動承認 (危険)
  NO_COLOR=1                   色を無効化
EOF
}

# ------------------------------------------------------------
# 非対話コマンド実装
# ------------------------------------------------------------
cmd_doctor()     { doctor_run "${1:-}"; }
cmd_prereq()     { prereq_report; }
cmd_config()     { print_banner; config_show; }

cmd_install() {
  local what="${1:-}"; shift || true
  case "$what" in
    hermes) install_hermes ;;
    omh)    install_omh "${1:-}" ;;
    *)
      log_error "install の対象を指定してください: hermes | omh"
      return 1
      ;;
  esac
}

cmd_setup() {
  local what="${1:-}"; shift || true
  case "$what" in
    omh) omh_setup_run "${1:-}" ;;
    *)   log_error "setup の対象を指定してください: omh" ; return 1 ;;
  esac
}

cmd_update() {
  local what="${1:-all}"
  case "$what" in
    hermes) update_hermes ;;
    omh)    update_omh ;;
    all)    update_hermes || true; update_omh || true ;;
    *)      log_error "update の対象: hermes | omh | all"; return 1 ;;
  esac
}

cmd_start() {
  local project="${1:-$(basename "$PWD")}"; shift || true
  session_start_foreground "$PWD" "$@"
}

cmd_bg() {
  local project="${1:-}" workdir="${2:-$PWD}"
  [[ -z "$project" ]] && { log_error "プロジェクト名を指定してください"; return 1; }
  session_start_background "$project" "$workdir"
}

cmd_sessions() {
  local sub="${1:-status}"
  case "$sub" in
    status|"") sessions_status ;;
    kill)      session_kill_all ;;
    *)         log_error "sessions: status | kill" ; return 1 ;;
  esac
}

cmd_attach() {
  local s="${1:-}"
  [[ -z "$s" ]] && { log_error "セッション名を指定してください"; return 1; }
  session_attach "$s"
}

cmd_skills() {
  local sub="${1:-summary}"; shift || true
  case "$sub" in
    summary|"") catalog_summary ;;
    list)       catalog_list_skills ;;
    search)     catalog_search "${1:-}" ;;
    family)     catalog_family_detail "${1:-}" ;;
    all|show)   catalog_show ;;
    *)          log_error "skills: summary | list | search <p> | family <id> | show"; return 1 ;;
  esac
}

cmd_workflows() { print_banner; workflow_catalog_view; }

cmd_routing() {
  local sub="${1:-status}"; shift || true
  case "$sub" in
    status|"") routing_status ;;
    validate)  routing_validate ;;
    seed)      routing_seed ;;
    guidance)  routing_guidance ;;
    readiness) routing_readiness ;;
    set)       routing_set_chain "$@" ;;
    *)         log_error "routing: status | validate | seed | readiness | guidance | set <cat> <m...>"; return 1 ;;
  esac
}

cmd_memory() {
  local sub="${1:-status}"; shift || true
  case "$sub" in
    status|"") memory_status ;;
    backup)    memory_backup "${1:-}" ;;
    list)      memory_list_backups "${1:-}" ;;
    restore)   memory_restore "${1:-}" ;;
    guidance)  memory_guidance ;;
    *)         log_error "memory: status | backup | list | restore <f> | guidance"; return 1 ;;
  esac
}

cmd_profiles() {
  local sub="${1:-status}"; shift || true
  case "$sub" in
    status|"") profiles_status ;;
    sync)      profiles_sync ;;
    inspect)   profile_inspect "${1:-}" ;;
    *)         log_error "profiles: status | sync | inspect <name>"; return 1 ;;
  esac
}

cmd_gateway() {
  local sub="${1:-status}"
  case "$sub" in
    status|"") gateway_status ;;
    setup)     gateway_setup ;;
    start)     gateway_start_background ;;
    stop)      gateway_stop ;;
    guidance)  gateway_guidance ;;
    *)         log_error "gateway: status | setup | start | stop | guidance"; return 1 ;;
  esac
}

cmd_evidence() {
  local sub="${1:-rules}"; shift || true
  case "$sub" in
    rules|"") evidence_rules_text ;;
    write)    local p; p="$(evidence_write_rules "${1:-}")"; log_ok "書き出しました: $p" ;;
    check)    evidence_selfcheck ;;
    *)        log_error "evidence: rules | write [path] | check"; return 1 ;;
  esac
}

cmd_loop() {
  local sub="${1:-list}"; shift || true
  case "$sub" in
    list|"")   loop_list ;;
    new)       loop_create "${1:-}" "${2:-}" ;;
    iterate)   loop_iterate "${1:-}" "${2:-}" "${3:-}" "${4:-}" "${5:-}" ;;
    show)      loop_show "${1:-}" ;;
    close)     loop_close "${1:-}" "${2:-}" "${3:-}" ;;
    guidance)  loop_guidance ;;
    *)         log_error "loop: list | new <title> <obj> | iterate <slug> <hyp> <act> <verify> <dec> | show <slug> | close <slug> <status> <sum> | guidance"; return 1 ;;
  esac
}

cmd_emit_rules() {
  print_banner
  log_step "実行規約を HERMES_HOME へ書き出す"
  local e w
  e="$(evidence_write_rules)"
  w="$(workflow_write_catalog)"
  log_ok "evidence 規約: $e"
  log_ok "workflow 集  : $w"
  log_dim "  Hermes のセッションから参照させるには、これらのパスを指示に含めてください。"
  log_dim "  例: 'EVIDENCE_RULES.md と WORKFLOWS.md に従って作業してください'"
}

# ------------------------------------------------------------
# 対話メニュー
# ------------------------------------------------------------
main_menu() {
  while true; do
    clear 2>/dev/null || true
    print_banner

    ! hermes_installed && printf '  %s⚠ Hermes 未導入 — [1] を実行してください%s\n' "$C_YELLOW" "$C_RESET"
    ! omh_installed    && printf '  %s⚠ OMH 未導入    — [2] を実行してください%s\n' "$C_YELLOW" "$C_RESET"
    if hermes_installed && omh_installed; then
      if omh_is_setup; then
        printf '  %s✓ Hermes + OMH 準備完了%s\n' "$C_GREEN" "$C_RESET"
      else
        printf '  %s⚠ OMH 未 setup  — [3] を実行してください%s\n' "$C_YELLOW" "$C_RESET"
      fi
    fi
    printf '\n'

    cat <<EOF
  ${C_BOLD}導入${C_RESET}
   1) Hermes 本体を導入              2) OMH を導入
   3) omh setup (skills + 登録)      4) 統合診断 (doctor)
   5) 更新 (hermes / omh)

  ${C_BOLD}実行${C_RESET}
   6) Hermes を起動 (対話)           7) バックグラウンド起動 (tmux)
   8) セッション監視                 9) Gateway

  ${C_BOLD}能力${C_RESET}
  10) スキルカタログ                11) ワークフロー集
  12) モデルルーティング            13) プロジェクト記憶
  14) プロファイル / bot

  ${C_BOLD}規約${C_RESET}
  15) Evidence boundaries           16) Loop Engineering
  17) 実行規約を書き出す

  18) 実効設定の表示                19) 前提コマンド検査
   h) ヘルプ                         q) 終了
EOF
    printf '\n%s選択:%s ' "$C_BOLD" "$C_RESET"
    local choice
    read -r choice || break

    case "$choice" in
      1)  install_hermes || true ;;
      2)  install_omh || true ;;
      3)  omh_setup_run || true ;;
      4)  doctor_run || true ;;
      5)  cmd_update all || true ;;
      6)  _menu_start_interactive ;;
      7)  _menu_start_background ;;
      8)  sessions_status || true ;;
      9)  _menu_gateway ;;
      10) _menu_skills ;;
      11) workflow_catalog_view ;;
      12) routing_status; printf '\n'; routing_readiness || true; _pause ;;
      13) memory_status; _pause ;;
      14) profiles_status; _pause ;;
      15) evidence_rules_text; _pause ;;
      16) loop_guidance; _pause ;;
      17) cmd_emit_rules ;;
      18) config_show; _pause ;;
      19) prereq_report || true; _pause ;;
      h|H|help) usage; _pause ;;
      q|Q|quit|exit) log_info "終了します。"; return 0 ;;
      "") : ;;
      *) log_warn "不明な選択: $choice"; _pause ;;
    esac
  done
}

_pause() {
  printf '\n%sEnter で戻る%s' "$C_DIM" "$C_RESET"
  read -r _ || true
}

_menu_start_interactive() {
  local project args
  printf 'プロジェクト名 (tmux 表示用, 既定: %s): ' "$(basename "$PWD")"
  read -r project || true
  [[ -z "$project" ]] && project="$(basename "$PWD")"
  printf 'hermes への追加引数 (無ければ Enter): '
  read -r args || true

  if [[ -n "$args" ]]; then
    # shellcheck disable=SC2086
    session_start_foreground "$PWD" $args || true
  else
    session_start_foreground "$PWD" || true
  fi
}

_menu_start_background() {
  local project workdir
  printf 'プロジェクト名 (既定: %s): ' "$(basename "$PWD")"
  read -r project || true
  [[ -z "$project" ]] && project="$(basename "$PWD")"
  printf '作業ディレクトリ (既定: %s): ' "$PWD"
  read -r workdir || true
  [[ -z "$workdir" ]] && workdir="$PWD"
  session_start_background "$project" "$workdir" || true
  _pause
}

_menu_gateway() {
  printf '\n 1) 状態  2) 接続先設定  3) 起動  4) 停止  5) 指針\n選択: '
  local c; read -r c || return 0
  case "$c" in
    1) gateway_status ;;
    2) gateway_setup || true ;;
    3) gateway_start_background || true ;;
    4) gateway_stop ;;
    5) gateway_guidance ;;
    *) log_warn "不明な選択" ;;
  esac
  _pause
}

_menu_skills() {
  printf '\n 1) 要約  2) 全スキル一覧  3) 検索  4) ファミリー詳細  5) 全ファミリー\n選択: '
  local c; read -r c || return 0
  case "$c" in
    1) catalog_summary ;;
    2) catalog_list_skills | less -R 2>/dev/null || catalog_list_skills ;;
    3) printf '検索語: '; local q; read -r q || return 0; catalog_search "$q" ;;
    4) printf 'family id: '; local f; read -r f || return 0; catalog_family_detail "$f" ;;
    5) catalog_show ;;
    *) log_warn "不明な選択" ;;
  esac
  _pause
}

# ------------------------------------------------------------
# ディスパッチ
# ------------------------------------------------------------
main() {
  local cmd="${1:-}"

  if [[ -z "$cmd" ]]; then
    os_assert_supported
    main_menu
    return 0
  fi

  shift || true
  case "$cmd" in
    doctor)      cmd_doctor "$@" ;;
    prereq)      print_banner; cmd_prereq ;;
    config)      cmd_config ;;
    install)     os_assert_supported; cmd_install "$@" ;;
    setup)       os_assert_supported; cmd_setup "$@" ;;
    update)      os_assert_supported; cmd_update "$@" ;;
    start)       os_assert_supported; cmd_start "$@" ;;
    bg)          os_assert_supported; cmd_bg "$@" ;;
    sessions)    cmd_sessions "$@" ;;
    attach)      cmd_attach "$@" ;;
    skills)      cmd_skills "$@" ;;
    workflows)   cmd_workflows ;;
    routing)     cmd_routing "$@" ;;
    memory)      cmd_memory "$@" ;;
    profiles)    cmd_profiles "$@" ;;
    gateway)     os_assert_supported; cmd_gateway "$@" ;;
    evidence)    cmd_evidence "$@" ;;
    loop)        cmd_loop "$@" ;;
    emit-rules)  cmd_emit_rules ;;
    help|-h|--help) usage ;;
    *)           log_error "不明なコマンド: $cmd"; printf '\n'; usage; return 1 ;;
  esac
}

main "$@"
