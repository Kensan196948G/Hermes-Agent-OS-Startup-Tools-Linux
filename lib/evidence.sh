#!/usr/bin/env bash
# ============================================================
# evidence.sh — Evidence boundaries (根拠境界) 実行規約
#
# 目的:
#   AI の「もっともらしい完了報告」と「未検証の断定」を減らす。
#   すべての主張を次のいずれかに分類することを強制する。
#
#   OBSERVED  : 実際にコマンド出力・ファイル・ログで確認した
#   PREPARED  : 成果物は作ったが、実行・適用・検証はしていない
#   PROPOSED  : 提案・設計であり、存在もし実行もしていない
#   NOT_OBSERVED : 確認していない (不明)
#
# 重要: 「未確認」を PASS と偽らない。空欄は NOT_OBSERVED である。
# ============================================================

if [[ -n "${__HERMESOS_EVIDENCE_SH:-}" ]]; then
  return 0
fi
__HERMESOS_EVIDENCE_SH=1

readonly EVIDENCE_CLASSES=(OBSERVED PREPARED PROPOSED NOT_OBSERVED)

# evidence_rules_text — Hermes へ渡す / 人間が読む規約本文
evidence_rules_text() {
  cat <<'RULES'
## Evidence boundaries (根拠境界) — 実行規約

すべての主張を次の4区分のいずれかに分類して報告すること。

| 区分 | 意味 | 必要な根拠 |
|---|---|---|
| OBSERVED | 実際に確認した | 実行したコマンドとその出力、読んだファイルパス |
| PREPARED | 作ったが未実行・未適用 | 作成したファイルパス。実行結果は主張しない |
| PROPOSED | 提案・設計のみ | 存在しない。実装も検証もしていない |
| NOT_OBSERVED | 確認していない | 不明であることを明示する |

### 禁止事項
1. PREPARED を OBSERVED として報告すること
   - 例: plan を書いた → 「migration 適用済み」と報告する
2. 実行していないテストを「通過した」と報告すること
3. 出力を確認せずに「成功しました」と報告すること
4. NOT_OBSERVED を空欄または省略で隠すこと

### 必須事項
- 各主張に最小の観測可能な証拠を添える (コマンド / パス / 出力行)
- 証拠が無い場合は NOT_OBSERVED と書き、次の一歩を添える
- ファイルを作っただけなら PREPARED と書き、検証を次段に明示する

### 報告テンプレート
```
### OBSERVED (確認済み)
- <主張>
  根拠: `<実行コマンド>` → <出力の要点>

### PREPARED (作成済み・未実行)
- <成果物パス>

### PROPOSED (提案)
- <提案内容>

### NOT_OBSERVED (未確認)
- <不明点> — 確認する最小の手順: <コマンド>
```
RULES
}

# evidence_write_rules <dest> — 規約ファイルを書き出す
evidence_write_rules() {
  local dest="${1:-${HERMES_HOME}/EVIDENCE_RULES.md}"
  mkdir -p "$(dirname "$dest")"
  {
    printf '# Evidence boundaries — 根拠境界 実行規約\n\n'
    printf '> このファイルは %s が生成しました。手で編集して構いません。\n' "$HERMESOS_NAME"
    printf '> 生成日時: %s\n\n' "$(date '+%Y-%m-%d %H:%M:%S')"
    evidence_rules_text
  } > "$dest"
  printf '%s' "$dest"
}

# evidence_classify_prompt — Hermes セッションへ投入する指示文
evidence_classify_prompt() {
  cat <<'PROMPT'
この作業の報告では evidence boundaries 規約に従ってください。
すべての主張を OBSERVED / PREPARED / PROPOSED / NOT_OBSERVED に分類し、
OBSERVED には実行コマンドと出力の要点を添えてください。
確認していないことを「完了」「成功」と書かないでください。
PROMPT
}

# evidence_selfcheck — 本ツール自身の出力が規約を守っているかの自己点検
#   ファイルの存在 = OBSERVED と言えるか、を機械的に確認する
#
#   重要: 「観測が0件」のときに「実測に基づいています」と言ってはならない。
#   それは規約違反そのものである。観測数を数え、0件なら合格としない。
evidence_selfcheck() {
  log_step "Evidence self-check (本ツールの主張の検証)"
  local fail=0 observed=0

  local hcmd; hcmd="$(hermes_cmd)"
  if hermes_installed; then
    local v; v="$("$hcmd" --version 2>/dev/null | head -1)"
    if [[ -n "$v" ]]; then
      check_pass "OBSERVED: hermes --version → $v"
      observed=$((observed + 1))
    else
      check_warn "PREPARED: hermes コマンドはあるが --version が出力を返さない"
      fail=1
    fi
  else
    check_skip "NOT_OBSERVED: hermes 未導入のためバージョン未確認"
  fi

  local ocmd; ocmd="$(omh_cmd)"
  if omh_installed; then
    local v; v="$("$ocmd" --version 2>/dev/null | head -1)"
    if [[ -n "$v" ]]; then
      check_pass "OBSERVED: omh --version → $v"
      observed=$((observed + 1))
    else
      check_warn "PREPARED: omh コマンドはあるが --version が出力を返さない"
      fail=1
    fi
  else
    check_skip "NOT_OBSERVED: omh 未導入のためバージョン未確認"
  fi

  # カタログ件数はファイル実在に基づく観測
  if [[ -f "$CATALOG_FILE" ]]; then
    local n; n="$(snapshot_skill_count)"
    if [[ "$n" -gt 0 ]]; then
      check_pass "OBSERVED: カタログ snapshot のスキル件数 = $n (根拠: $CATALOG_FILE)"
      observed=$((observed + 1))
    fi
  fi

  printf '\n'
  if [[ "$observed" -eq 0 ]]; then
    check_warn "OBSERVED な主張が 0 件です。本ツールの出力は実測に基づいていません。"
    log_dim "  対処: Hermes/OMH を導入すると実測が可能になります。"
    return 1
  fi
  if [[ "$fail" -ne 0 ]]; then
    check_warn "未確認または矛盾する主張があります。上記の NOT_OBSERVED / PREPARED を確認してください。"
    return 1
  fi

  check_pass "OBSERVED $observed 件・矛盾なし — 主張は実測に基づいています"
  return 0
}
