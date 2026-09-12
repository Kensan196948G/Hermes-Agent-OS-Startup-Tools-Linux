#!/usr/bin/env bash
# ============================================================
# routing.sh — モデルルーティング
#
# 事実 (upstream で確認):
#   ユーザーのチェーンカスタマイズ文書:
#     ~/.omh/routing/model-chains.json
#     schema: mixture_chain_overrides/v1
#     categories が空 = 出荷時既定が適用される
#   書き込んだ category が routing / fallback / HUD ラベルを支配する。
#   対話的なモデル設定は Hermes 側の skill で行う:  /omh-model-setup
#
# 方針:
#   本ツールは「既存の割当を壊さない」。編集は必ずバックアップを取る。
# ============================================================

if [[ -n "${__HERMESOS_ROUTING_SH:-}" ]]; then
  return 0
fi
__HERMESOS_ROUTING_SH=1

readonly ROUTING_SCHEMA="mixture_chain_overrides/v1"

routing_file() { printf '%s' "$OMH_MODEL_CHAINS"; }

routing_exists() { [[ -f "$OMH_MODEL_CHAINS" ]]; }

# routing_status — 現在のルーティング状態を表示
routing_status() {
  printf '%sモデルルーティング%s\n' "$C_BOLD" "$C_RESET"
  printf '  %-22s %s\n' "chain file" "$OMH_MODEL_CHAINS"

  if ! routing_exists; then
    log_warn "model-chains.json がありません。"
    log_dim "  omh setup が seed します。それまでは出荷時既定が適用されます。"
    return 1
  fi

  if ! json_valid "$OMH_MODEL_CHAINS"; then
    log_error "model-chains.json が不正な JSON です。ルーティングが既定に戻ります。"
    log_dim "  対処: cp $OMH_MODEL_CHAINS $OMH_MODEL_CHAINS.bak してから修正"
    return 1
  fi

  local schema cats n
  schema="$(json_get "$OMH_MODEL_CHAINS" '.schema_version' 'unknown')"
  n="$(json_get "$OMH_MODEL_CHAINS" '.categories | length' '0')"

  printf '  %-22s %s\n' "schema" "$schema"
  printf '  %-22s %s\n' "categories (上書き)" "$n"

  if [[ "$schema" != "$ROUTING_SCHEMA" ]]; then
    log_warn "想定スキーマ ($ROUTING_SCHEMA) と異なります。上流の更新を確認してください。"
  fi

  if [[ "$n" == "0" ]]; then
    log_dim "  categories が空 = 出荷時既定のチェーンが適用されています。"
    return 0
  fi

  printf '\n%s上書きされているカテゴリ%s\n' "$C_BOLD" "$C_RESET"
  jq -r '.categories | to_entries[] | "  \(.key): \(.value | if type == "array" then join(" → ") else tostring end)"' \
    "$OMH_MODEL_CHAINS" 2>/dev/null
  return 0
}

# routing_backup — 編集前のバックアップ
routing_backup() {
  routing_exists || return 1
  local dest
  dest="${OMH_MODEL_CHAINS}.bak.$(date +%Y%m%d%H%M%S)"
  cp "$OMH_MODEL_CHAINS" "$dest"
  log_ok "バックアップ: $dest"
  printf '%s' "$dest"
}

# routing_seed — 無い場合に空の上書き文書を作る (omh setup と同じ形)
routing_seed() {
  if routing_exists && [[ "${HERMESOS_FORCE:-0}" != "1" ]]; then
    log_info "model-chains.json は既に存在します: $OMH_MODEL_CHAINS"
    return 0
  fi
  json_available || { log_error "jq が必要です。"; return 1; }
  mkdir -p "$OMH_ROUTING_DIR"

  jq -n --arg schema "$ROUTING_SCHEMA" \
    '{schema_version: $schema, categories: {}}' > "$OMH_MODEL_CHAINS"

  log_ok "model-chains.json を作成しました (categories は空 = 出荷時既定): $OMH_MODEL_CHAINS"
  log_dim "  category を書くと routing / fallback / HUD ラベルが変わります。"
  return 0
}

# routing_set_chain <category> <model1> [model2...]
routing_set_chain() {
  local category="$1"; shift
  routing_exists || { log_error "model-chains.json がありません。先に seed してください。"; return 1; }
  json_available || { log_error "jq が必要です。"; return 1; }

  local models_json
  models_json="$(printf '%s\n' "$@" | jq -R . | jq -s .)"

  routing_backup >/dev/null

  local tmp; tmp="$(mktemp)"
  jq --arg cat "$category" --argjson chain "$models_json" \
    '.categories[$cat] = $chain' "$OMH_MODEL_CHAINS" > "$tmp" && mv "$tmp" "$OMH_MODEL_CHAINS"

  log_ok "カテゴリ '$category' のチェーンを設定しました"
  printf '%s' "$models_json" | jq -r '"  " + join(" → ")'
  log_dim "  有効化には Hermes の再起動が必要です。"
}

# routing_validate — 検証のみ
routing_validate() {
  if ! routing_exists; then
    check_fail "model-chains.json が存在しない: $OMH_MODEL_CHAINS"
    return 1
  fi
  if json_valid "$OMH_MODEL_CHAINS"; then
    check_pass "model-chains.json は有効な JSON"
  else
    check_fail "model-chains.json が不正な JSON"
    return 1
  fi
  local schema; schema="$(json_get "$OMH_MODEL_CHAINS" '.schema_version' 'unknown')"
  if [[ "$schema" == "$ROUTING_SCHEMA" ]]; then
    check_pass "schema_version = $ROUTING_SCHEMA"
  else
    check_warn "schema_version が想定外: $schema"
  fi
  return 0
}

# routing_guidance — ルーティング設計の指針
routing_guidance() {
  cat <<'GUIDE'
## Model routing — 設計指針

高コストモデルを常用しない。仕事の性質で振り分ける。

| 仕事 | 適した性質 | 理由 |
|---|---|---|
| 調査・収集 | 安価で高速 | 反復が多く、外れても損失が小さい |
| 計画・設計 | 高能力 | 誤ると後工程すべてが無駄になる |
| 実装 | 中〜高能力 + 長いコンテキスト | 既存コードの文脈理解が要る |
| レビュー・検証 | 実装とは別系統 | 同一モデルは自分の誤りを見落とす |
| 定型・整形 | 最安 | 判断を要さない |

### 設定方法
1. 対話設定: Hermes 内で `/omh-model-setup` を実行
2. 直接編集: ~/.omh/routing/model-chains.json の categories に追記
   - fallback を必ず2件以上にする (1件だと障害時に停止する)
   - 言語別に振る場合は、その言語のトークン効率が良いモデルを選ぶ

### 注意
- categories を空にすると出荷時既定に戻る。壊したら空に戻すのが最速の復旧。
- 変更は Hermes の再起動で反映される。
GUIDE
}

# ---------------------------------------------------------------
# routing_readiness — ルーティングの「準備度」を上流から要約する
#
#   事実 (実測):
#     'omh coding model-routing status --json' は
#     schema_version model_routing_status/v1 の JSON を返す。
#     生出力は 100KB 超になり得る (discovered が 668 件等)。
#     そこで本関数は判断に必要な要点だけを抽出する。
#
#   上流の主張の境界 (そのまま尊重する):
#     「discovered は実行証明ではない。confirmed-active は権限・資格情報の
#       有効性・ディスパッチ・実行・レビュー・CI・マージの証拠ではない。
#       ネットワーク要求は行っていない。」
# ---------------------------------------------------------------

# routing_status_json — 上流 JSON を取得 (失敗時は空)
routing_status_json() {
  omh_installed || return 0
  [[ "$DRY_RUN" == "1" ]] && return 0
  timeout 90 "$(omh_cmd)" coding model-routing status --json 2>/dev/null
}

routing_readiness() {
  if ! omh_installed; then
    check_fail "omh が未導入のため準備度を取得できません"
    return 1
  fi

  # 注意: 'local json="$(...)"' と書いてはならない。
  # 宣言が command substitution の終了コードを返し、set -e が
  # スクリプトごと落として graceful な失敗処理に到達しない。
  # (この欠陥は実際に発生した。失敗経路のテストで検出)
  local json
  json="$(routing_status_json)" || json=""

  if [[ -z "$json" ]] || ! printf '%s' "$json" | jq empty >/dev/null 2>&1; then
    printf '%sモデルルーティング準備度%s\n' "$C_BOLD" "$C_RESET"
    check_warn "上流の model-routing status を取得できません"
    log_dim "  原因候補: omh の失敗 / JSON 不正 / タイムアウト"
    log_dim "  手動確認: omh coding model-routing status"
    return 1
  fi

  local status next confirmed discovered truncated
  status="$(printf '%s' "$json" | jq -r '.status // "unknown"')"
  next="$(printf '%s' "$json" | jq -r '.next_action // ""')"
  confirmed="$(printf '%s' "$json" | jq -r '.models.confirmed | length')"
  discovered="$(printf '%s' "$json" | jq -r '.models.discovered_only | length')"
  truncated="$(printf '%s' "$json" | jq -r '.models.discovery_truncated // false')"

  printf '%sモデルルーティング準備度%s\n' "$C_BOLD" "$C_RESET"
  printf '  %-24s %s\n' "upstream status" "$status"
  printf '  %-24s %s\n' "confirmed (実行に使える)" "$confirmed"
  printf '  %-24s %s\n' "discovered_only (証明でない)" "$discovered"
  [[ "$truncated" == "true" ]] && printf '  %-24s %s\n' "discovery" "truncated (全件ではない)"

  # モデル名列挙はdedupeして件数だけ示す (668 件を並べても判断に使えない)
  local uniq_discovered
  uniq_discovered="$(printf '%s' "$json" | jq -r '[.models.discovered_only[].model_id] | unique | .[]' 2>/dev/null | grep -c . || true)"
  printf '  %-24s %s\n' "discovered ユニーク名" "${uniq_discovered:-0}"

  printf '\n%sモデルソースの観測状態%s\n' "$C_BOLD" "$C_RESET"
  printf '%s\n' "$json" | jq -r '.models.source_statuses | to_entries[] | "  \(.key): \(.value)"' 2>/dev/null

  # Hermes alias と Maestro の欠落 head
  printf '\n%sHermes aliases%s\n' "$C_BOLD" "$C_RESET"
  printf '  %-24s %s\n' "status" "$(printf '%s' "$json" | jq -r '.hermes.status // "unknown"')"
  printf '  %-24s %s\n' "recommended_head" "$(printf '%s' "$json" | jq -r '.hermes.recommendation.recommended_head // "none"')"

  local missing
  missing="$(printf '%s' "$json" | jq -r '[.maestro.missing_heads[]] | join(", ")')"
  printf '\n%sMaestro の欠落 head%s\n' "$C_BOLD" "$C_RESET"
  if [[ -n "$missing" && "$missing" != "null" ]]; then
    printf '  %s\n' "$missing"
  else
    printf '  (なし)\n'
  fi

  printf '\n%sowner learning%s\n' "$C_BOLD" "$C_RESET"
  printf '  %-24s %s\n' "status" "$(printf '%s' "$json" | jq -r '.owner_learning.status // "unknown"')"
  printf '  %-24s %s\n' "path" "$(printf '%s' "$json" | jq -r '.owner_learning.path // "-"')"

  if [[ -n "$next" && "$next" != "null" ]]; then
    printf '\n%snext_action%s\n  → %s\n' "$C_BOLD" "$C_RESET" "$next"
  fi

  # 上流の境界表明をそのまま伝える (要約で消さない)
  local boundary
  boundary="$(printf '%s' "$json" | jq -r '.claim_boundary // ""')"
  printf '\n%s上流の主張境界%s\n' "$C_DIM" "$C_RESET"
  if [[ -n "$boundary" && "$boundary" != "null" ]]; then
    printf '%s  %s%s\n' "$C_DIM" "$boundary" "$C_RESET"
  else
    log_dim "  discovered は実行証明ではない。confirmed は権限・資格情報・実行の証拠ではない。"
    log_dim "  ネットワーク要求は行われていない。"
  fi
  printf '\n'

  if [[ "$confirmed" -eq 0 ]]; then
    check_warn "confirmed が 0 件です。ルーティングは未確定 (実行時の委譲先は未証明)"
    return 2
  fi
  check_pass "confirmed $confirmed 件"
  return 0
}
