#!/usr/bin/env bash
# ============================================================
# helper.bash — bats テスト共通ヘルパ
#
# テスト方針:
#   実環境 (~/.hermes, ~/.omh) を汚さない。必ず一時 HOME に隔離する。
#   Hermes/OMH が未導入でもテストが通るように、必要ならスタブを置く。
# ============================================================

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
readonly PROJECT_ROOT
export PROJECT_ROOT

# ---------------------------------------------------------------
# 検出の隔離
#
#   hermes_installed() / omh_installed() は has_cmd (PATH 検索) と
#   既知の絶対パスの両方を見る。したがって「未導入であること」を
#   前提にするテストは、PATH に ~/.local/bin が含まれていると
#   *実インストールを検出して* 落ちる。
#   (この欠陥は実際に発生し、5 件がホスト依存で失敗した)
#
#   HERMES_BIN/OMH_BIN の差し替えだけでは不十分である。
#   has_cmd が PATH 上の実バイナリを見つけてしまうため、
#   空ディレクトリを PATH の先頭に置いて PATH 検索も塞ぐ。
# ---------------------------------------------------------------
# isolate_no_install <workdir>
#   「Hermes / OMH が未導入」の状態を決定論的に再現する環境変数を
#   標準出力に KEY=VALUE 形式で返す (env へ渡すため)。
isolate_no_install_env() {
  local workdir="$1"
  local empty="${workdir}/empty-path"
  mkdir -p "$empty"
  printf 'PATH=%s ' "${empty}:/usr/bin:/bin"
  printf 'HERMES_BIN=%s ' "${workdir}/__no_hermes__"
  printf 'OMH_BIN=%s ' "${workdir}/__no_omh__"
}

# 隔離された HOME + 未導入検出 で start.sh を実行する
#   run_iso <args...>
run_iso() {
  local tmp_home empty
  tmp_home="$(mktemp -d)"
  empty="${tmp_home}/empty-path"
  mkdir -p "$empty"

  HOME="$tmp_home" NO_COLOR=1 \
    PATH="${empty}:/usr/bin:/bin" \
    HERMES_BIN="${tmp_home}/__no_hermes__" \
    OMH_BIN="${tmp_home}/__no_omh__" \
    "$PROJECT_ROOT/start.sh" "$@" 2>&1
  local rc=$?
  rm -rf "$tmp_home"
  return $rc
}

# 隔離 HOME で実行し、標準出力をそのまま返す (終了コードは捨てる)
iso() {
  local tmp_home empty
  tmp_home="$(mktemp -d)"
  empty="${tmp_home}/empty-path"
  mkdir -p "$empty"

  HOME="$tmp_home" NO_COLOR=1 \
    PATH="${empty}:/usr/bin:/bin" \
    HERMES_BIN="${tmp_home}/__no_hermes__" \
    OMH_BIN="${tmp_home}/__no_omh__" \
    "$PROJECT_ROOT/start.sh" "$@" 2>&1 || true
  rm -rf "$tmp_home"
}

# stub_hermes <dir> — PATH に置く偽 hermes を作る
stub_hermes() {
  local dir="$1"
  cat > "${dir}/hermes" <<'STUB'
#!/usr/bin/env bash
case "${1:-}" in
  --version) echo "hermes 0.0.0-stub" ;;
  update)    echo "stub: update"; exit 0 ;;
  doctor)    echo "stub: doctor ok"; exit 0 ;;
  *)         echo "stub hermes: $*"; exit 0 ;;
esac
STUB
  chmod +x "${dir}/hermes"
}

# stub_omh <dir> — PATH に置く偽 omh を作る
stub_omh() {
  local dir="$1"
  cat > "${dir}/omh" <<'STUB'
#!/usr/bin/env bash
case "${1:-}" in
  --version) echo "omh 0.0.0-stub" ;;
  doctor)    echo "stub: omh doctor ok"; exit 0 ;;
  *)         echo "stub omh: $*"; exit 0 ;;
esac
STUB
  chmod +x "${dir}/omh"
}

# assert_output_contains <needle>
assert_output_contains() {
  if [[ "$output" != *"$1"* ]]; then
    printf 'expected output to contain: %s\n--- actual ---\n%s\n' "$1" "$output" >&2
    return 1
  fi
}

# assert_output_not_contains <needle>
assert_output_not_contains() {
  if [[ "$output" == *"$1"* ]]; then
    printf 'expected output NOT to contain: %s\n--- actual ---\n%s\n' "$1" "$output" >&2
    return 1
  fi
}
