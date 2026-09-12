#!/usr/bin/env bash
# ============================================================
# memory.sh — プロジェクト記憶 (Agentic Memory) の扱い
#
# 事実 (upstream で確認):
#   Hermes は agent-curated memory を持ち、定期的に永続化を促す(nudge)。
#   FTS5 によるセッション検索と LLM 要約でセッション横断想起を行う。
#   Honcho による dialectic user modeling に対応。
#   データ領域は HERMES_HOME (既定 ~/.hermes)。
#
# 方針:
#   本ツールは Hermes の記憶を書き換えない。所在の可視化と、
#   バックアップ/復元の安全な経路だけを提供する。
# ============================================================

if [[ -n "${__HERMESOS_MEMORY_SH:-}" ]]; then
  return 0
fi
__HERMESOS_MEMORY_SH=1

# memory_paths — 記憶関連の候補パスを列挙 (存在するものだけ)
#
#   実測 (hermes doctor が確認した権威ある配置):
#     ~/.hermes/memories/MEMORY.md  ← エージェントが最初に記憶を書くと作成される
#     ~/.hermes/memories/USER.md    ← 同上
#     ~/.hermes/state.db            ← セッション/メッセージの DB (FTS5)
#     ~/.omh/runtime/state.json     ← OMH のランタイム状態ログ
memory_paths() {
  local cands=(
    "$HERMES_MEMORY_DIR"
    "${HERMES_MEMORY_DIR}/MEMORY.md"
    "${HERMES_MEMORY_DIR}/USER.md"
    "$HERMES_STATE_DB"
    "$HERMES_HOME/honcho"
    "$OMH_HOME/runtime/state.json"
  )
  local p
  for p in "${cands[@]}"; do
    [[ -e "$p" ]] && printf '%s\n' "$p"
  done | awk '!seen[$0]++'
  return 0
}

# memory_expected_paths — 期待されるが未作成のものも含めて報告する
memory_expected_paths() {
  printf '%s\n' \
    "${HERMES_MEMORY_DIR}/MEMORY.md" \
    "${HERMES_MEMORY_DIR}/USER.md"
}

# memory_status — 記憶領域の状態表示
memory_status() {
  printf '%sプロジェクト記憶 / Agentic Memory%s\n' "$C_BOLD" "$C_RESET"
  printf '  %-22s %s\n' "HERMES_HOME" "$HERMES_HOME"

  if [[ ! -d "$HERMES_HOME" ]]; then
    log_warn "HERMES_HOME が存在しません。Hermes 初回起動時に作成されます。"
    return 1
  fi

  local found=0 p
  while IFS= read -r p; do
    [[ -z "$p" ]] && continue
    found=1
    if [[ -d "$p" ]]; then
      printf '  %s✓%s %s/ (%s ファイル)\n' "$C_GREEN" "$C_RESET" "$p" \
        "$(find "$p" -type f 2>/dev/null | grep -c . || true)"
    else
      printf '  %s✓%s %s (%s bytes)\n' "$C_GREEN" "$C_RESET" "$p" \
        "$(stat -c%s "$p" 2>/dev/null || printf '?')"
    fi
  done < <(memory_paths)

  if [[ "$found" -eq 0 ]]; then
    log_warn "既知の記憶パスが見つかりません。"
    log_dim "  記憶の実体は Hermes のバージョンにより配置が変わります。"
    log_dim "  正確な状態は 'hermes doctor' と Hermes 内の記憶コマンドで確認してください。"
    return 1
  fi

  # 期待されるが未作成のものは「無い」と明示する (空欄で隠さない)
  local expected missing=()
  while IFS= read -r expected; do
    [[ -z "$expected" ]] && continue
    [[ -e "$expected" ]] || missing+=("$expected")
  done < <(memory_expected_paths)

  if [[ "${#missing[@]}" -gt 0 ]]; then
    printf '\n  %s未作成 (エージェントが最初に記憶を書くと作成されます)%s\n' "$C_DIM" "$C_RESET"
    local m
    for m in "${missing[@]}"; do printf '    - %s\n' "$m"; done
  fi

  printf '\n%s注意%s: 本ツールは記憶の内容を解釈・改変しません。\n' "$C_YELLOW" "$C_RESET"
  log_dim "  記憶の参照・更新は Hermes 内の自然言語操作で行ってください。"
  return 0
}

# memory_backup [dest_dir]
memory_backup() {
  local dest="${1:-${HERMESOS_ROOT}/backups/memory}"
  if [[ ! -d "$HERMES_HOME" ]]; then
    log_error "HERMES_HOME が存在しません: $HERMES_HOME"
    return 1
  fi
  mkdir -p "$dest"
  local stamp; stamp="$(date +%Y%m%d-%H%M%S)"
  local archive="${dest}/hermes-home-${stamp}.tar.gz"

  local targets=()
  local c
  for c in memory memories honcho user config.yaml plugins skills sessions; do
    [[ -e "${HERMES_HOME}/${c}" ]] && targets+=("$c")
  done

  if [[ "${#targets[@]}" -eq 0 ]]; then
    log_warn "バックアップ対象が見つかりません。"
    return 1
  fi

  log_step "記憶・設定をバックアップ"
  log_dim "  対象: ${targets[*]}"
  if [[ "$DRY_RUN" == "1" ]]; then
    printf '%s[DRY-RUN]%s tar -czf %s -C %s %s\n' "$C_CYAN" "$C_RESET" "$archive" "$HERMES_HOME" "${targets[*]}"
    return 0
  fi

  tar -czf "$archive" -C "$HERMES_HOME" "${targets[@]}" 2>/dev/null || {
    log_error "バックアップに失敗しました。"
    return 1
  }
  chmod 600 "$archive" 2>/dev/null || true
  log_ok "バックアップ完了: $archive"
  log_dim "  サイズ: $(du -h "$archive" 2>/dev/null | cut -f1)"
  log_warn "認証情報が含まれる可能性があります。取り扱いに注意してください (権限 600 に設定済み)。"
  return 0
}

# memory_list_backups
memory_list_backups() {
  local dest="${1:-${HERMESOS_ROOT}/backups/memory}"
  if [[ ! -d "$dest" ]] || ! compgen -G "$dest/*.tar.gz" >/dev/null 2>&1; then
    log_info "バックアップはありません: $dest"
    return 0
  fi
  ls -lh "$dest"/*.tar.gz | awk '{printf "  %-10s %s %s  %s\n", $5, $6, $7, $9}'
}

# memory_restore <archive> — 破壊的操作なので必ず確認
memory_restore() {
  local archive="$1"
  [[ -f "$archive" ]] || { log_error "アーカイブがありません: $archive"; return 1; }

  log_warn "復元は現在の $HERMES_HOME の内容を上書きします。"
  printf '  アーカイブ: %s\n' "$archive"
  printf '  復元先    : %s\n' "$HERMES_HOME"

  confirm "本当に復元しますか? (既存の記憶・設定が上書きされます)" || {
    log_dim "中止しました。"
    return 1
  }

  # 復元前の退避
  local safety
  safety="${HERMES_HOME}.before-restore.$(date +%Y%m%d%H%M%S)"
  cp -a "$HERMES_HOME" "$safety" 2>/dev/null || log_warn "退避に失敗しましたが続行します。"
  log_dim "  退避: $safety"

  if [[ "$DRY_RUN" == "1" ]]; then
    printf '%s[DRY-RUN]%s tar -xzf %s -C %s\n' "$C_CYAN" "$C_RESET" "$archive" "$HERMES_HOME"
    return 0
  fi

  tar -xzf "$archive" -C "$HERMES_HOME" && log_ok "復元が完了しました" || {
    log_error "復元に失敗しました。退避 $safety から戻せます。"
    return 1
  }
  log_dim "  反映には Hermes の再起動が必要です。"
  return 0
}

# memory_guidance — 記憶運用の指針
memory_guidance() {
  cat <<'GUIDE'
## Agentic Memory — 運用指針

会話ログを「貯める」のではなく、根拠を伴うプロジェクト記憶として扱う。

### 記憶として残すべきもの
- 要件と、その背景
- 判断と、その理由 (なぜ他案を採らなかったか)
- 未解決課題と、次に確認すべきこと
- 検証結果と、その検証手段

### 記憶として残すべきでないもの
- 検証していない推測 (evidence boundaries の NOT_OBSERVED は記憶にしない)
- 一時的な雑談
- すぐ陳腐化する具体値 (バージョン番号など) — 参照先を残す

### 引き継ぎの型
```
要件        : <何を満たすべきか>
判断        : <何を決めたか>
理由        : <なぜか / 却下した代替案>
未解決      : <残っている問い>
検証済み    : <OBSERVED な事実とその根拠>
次の一歩    : <最小の確認手順>
```

### 注意
記憶の配置は Hermes のバージョンで変わる。本ツールは所在の可視化のみ行い、
内容の解釈・改変はしない。正確な状態は Hermes 内で確認すること。
GUIDE
}
