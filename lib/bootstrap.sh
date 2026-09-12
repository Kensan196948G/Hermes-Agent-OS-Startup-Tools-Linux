#!/usr/bin/env bash
# ============================================================
# bootstrap.sh — 全ライブラリの読込と初期化
#
# 呼び出し順序が重要:
#   common → config-loader (HERMES_HOME 等を決める) → paths (readonly 計算)
#   → 残りの機能ライブラリ
# ============================================================

if [[ -n "${__HERMESOS_BOOTSTRAP_SH:-}" ]]; then
  return 0
fi
__HERMESOS_BOOTSTRAP_SH=1

# common.sh は自分で ROOT/LIB を解決する
# shellcheck source=./common.sh
source "${BASH_SOURCE[0]%/*}/common.sh"

# 設定 → パスの順序を守る (paths.sh は readonly を確定させる)
# shellcheck source=./json.sh
source "${HERMESOS_LIB_DIR}/json.sh"
# shellcheck source=./yaml.sh
source "${HERMESOS_LIB_DIR}/yaml.sh"
# shellcheck source=./os-detect.sh
source "${HERMESOS_LIB_DIR}/os-detect.sh"
# shellcheck source=./config-loader.sh
source "${HERMESOS_LIB_DIR}/config-loader.sh"

# config を読む (環境変数 > config.json > 既定値)
config_load || true

# shellcheck source=./paths.sh
source "${HERMESOS_LIB_DIR}/paths.sh"

# 残りの機能
# shellcheck source=./prereq.sh
source "${HERMESOS_LIB_DIR}/prereq.sh"
# shellcheck source=./hermes-install.sh
source "${HERMESOS_LIB_DIR}/hermes-install.sh"
# shellcheck source=./omh-install.sh
source "${HERMESOS_LIB_DIR}/omh-install.sh"
# shellcheck source=./skills-catalog.sh
source "${HERMESOS_LIB_DIR}/skills-catalog.sh"
# shellcheck source=./workflow.sh
source "${HERMESOS_LIB_DIR}/workflow.sh"
# shellcheck source=./evidence.sh
source "${HERMESOS_LIB_DIR}/evidence.sh"
# shellcheck source=./loop.sh
source "${HERMESOS_LIB_DIR}/loop.sh"
# shellcheck source=./routing.sh
source "${HERMESOS_LIB_DIR}/routing.sh"
# shellcheck source=./memory.sh
source "${HERMESOS_LIB_DIR}/memory.sh"
# shellcheck source=./profiles.sh
source "${HERMESOS_LIB_DIR}/profiles.sh"
# shellcheck source=./gateway.sh
source "${HERMESOS_LIB_DIR}/gateway.sh"
# shellcheck source=./sessions.sh
source "${HERMESOS_LIB_DIR}/sessions.sh"
# shellcheck source=./doctor.sh
source "${HERMESOS_LIB_DIR}/doctor.sh"

mkdir -p "$HERMESOS_LOG_DIR" 2>/dev/null || true
