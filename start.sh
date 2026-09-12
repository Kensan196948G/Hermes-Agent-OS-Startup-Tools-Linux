#!/usr/bin/env bash
# ============================================================
# start.sh — HermesAgentOS StartUpTools 起動エントリ (Linux native)
#   運用管理メニュー (bin/menu.sh) を起動する。
#   引数はそのまま menu.sh へ渡す (例: --doctor, --list-skills)。
# ============================================================

set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "$ROOT/bin/menu.sh" "$@"
