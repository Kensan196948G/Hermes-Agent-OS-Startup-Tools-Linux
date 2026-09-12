#!/usr/bin/env bash
# ============================================================
# loop.sh — Loop Engineering 実行規約
#
# 目的:
#   不確実性の高い目標に対して、発見→実行→検証→修正を
#   反復する制御面を提供する。
#   例: 「既存システムを調査して改善案を作り、PoC まで進める」
#
# 設計:
#   1目標 = 1ループ台帳 (loop state file)。
#   各イテレーションは Hypothesis → Action → Verification → Decision
#   の4点を記録する。Verification が空のイテレーションは無効とする。
# ============================================================

if [[ -n "${__HERMESOS_LOOP_SH:-}" ]]; then
  return 0
fi
__HERMESOS_LOOP_SH=1

readonly LOOP_DIR_DEFAULT="${HERMESOS_ROOT}/state/loops"

loop_dir() { printf '%s' "${HERMESOS_LOOP_DIR:-$LOOP_DIR_DEFAULT}"; }

# loop_slug <title> — ファイル名に使える slug
loop_slug() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//' | cut -c1-48
}

# loop_path <slug>
loop_path() { printf '%s/%s.json' "$(loop_dir)" "$1"; }

# loop_create <title> <objective>
loop_create() {
  local title="$1" objective="$2"
  local slug; slug="$(loop_slug "$title")"
  local file; file="$(loop_path "$slug")"
  mkdir -p "$(loop_dir)"

  if [[ -f "$file" ]]; then
    log_warn "同名のループが既に存在します: $file"
    return 1
  fi

  if ! json_available; then
    log_error "jq が必要です。"
    return 1
  fi

  jq -n \
    --arg title "$title" \
    --arg objective "$objective" \
    --arg created "$(date -Iseconds)" \
    '{
      schema_version: "hermesos_loop/v1",
      title: $title,
      objective: $objective,
      created_at: $created,
      status: "open",
      iteration: 0,
      max_iterations: 10,
      iterations: []
    }' > "$file"

  log_ok "ループを作成しました: $file"
  return 0
}

# loop_list
loop_list() {
  local d; d="$(loop_dir)"
  if [[ ! -d "$d" ]] || ! compgen -G "$d/*.json" >/dev/null 2>&1; then
    log_info "ループがありません。'loop new <title> <objective>' で作成してください。"
    return 0
  fi
  printf '%s%-28s %-10s %-6s %s%s\n' "$C_BOLD" "SLUG" "STATUS" "ITER" "OBJECTIVE" "$C_RESET"
  local f
  for f in "$d"/*.json; do
    jq -r '"\(.title|ascii_downcase|gsub("[^a-z0-9]+";"-")|.[0:26])\t\(.status)\t\(.iteration)\t\(.objective|.[0:44])"' "$f" 2>/dev/null \
      || log_warn "読めないループファイル: $f"
  done | awk -F'\t' '{printf "%-28s %-10s %-6s %s\n", $1, $2, $3, $4}'
}

# loop_iterate <slug> <hypothesis> <action> <verification> <decision>
#   verification が空なら記録を拒否する (証拠なき反復を防ぐ)
loop_iterate() {
  local slug="$1" hyp="$2" action="$3" verify="$4" decision="$5"
  local file; file="$(loop_path "$slug")"

  [[ -f "$file" ]] || { log_error "ループがありません: $file"; return 1; }

  if [[ -z "${verify//[[:space:]]/}" ]]; then
    log_error "verification が空です。検証なき反復は記録できません (Loop Engineering 規約)。"
    log_dim "  検証手段の例: 実行したコマンド、確認した出力、読んだファイル"
    return 1
  fi

  local n; n="$(jq -r '.iteration' "$file")"
  n=$((n + 1))

  local tmp; tmp="$(mktemp)"
  jq \
    --argjson n "$n" \
    --arg ts "$(date -Iseconds)" \
    --arg hyp "$hyp" \
    --arg action "$action" \
    --arg verify "$verify" \
    --arg decision "$decision" \
    '.iteration = $n
     | .iterations += [{
         n: $n, at: $ts,
         hypothesis: $hyp, action: $action,
         verification: $verify, decision: $decision,
         evidence_class: "OBSERVED"
       }]' "$file" > "$tmp" && mv "$tmp" "$file"

  log_ok "イテレーション $n を記録しました ($slug)"
  log_dim "  検証: $verify"
  return 0
}

# loop_show <slug>
loop_show() {
  local file; file="$(loop_path "$1")"
  [[ -f "$file" ]] || { log_error "ループがありません: $file"; return 1; }

  jq -r '
    "title      : \(.title)
objective  : \(.objective)
status     : \(.status)
iteration  : \(.iteration) / \(.max_iterations)
created    : \(.created_at)",
    (if (.iterations | length) == 0 then "\n(イテレーション未記録)"
     else "\n" + ([.iterations[] |
       "── #\(.n)  \(.at)\n  hypothesis  : \(.hypothesis)\n  action      : \(.action)\n  verification: \(.verification)\n  decision    : \(.decision)"] | join("\n"))
     end)
  ' "$file"
}

# loop_close <slug> <status> <summary>
loop_close() {
  local slug="$1" status="$2" summary="$3"
  local file; file="$(loop_path "$slug")"
  [[ -f "$file" ]] || { log_error "ループがありません: $file"; return 1; }

  # 未検証のイテレーションが無いことを確認してから閉じる
  local unverified
  unverified="$(jq '[.iterations[] | select((.verification // "") == "")] | length' "$file")"
  if [[ "$unverified" -gt 0 ]]; then
    log_error "検証が空のイテレーションが $unverified 件あります。閉じられません。"
    return 1
  fi

  local tmp; tmp="$(mktemp)"
  jq --arg s "$status" --arg sum "$summary" --arg ts "$(date -Iseconds)" \
    '.status = $s | .summary = $sum | .closed_at = $ts' "$file" > "$tmp" && mv "$tmp" "$file"
  log_ok "ループを $status で閉じました ($slug)"
}

# loop_guidance — ループ設計の指針本文
loop_guidance() {
  cat <<'GUIDE'
## Loop Engineering — 反復規約

不確実性の高い目標は、一度で正解を出すのではなく次の4点を反復する。

1. Hypothesis (仮説)  — 何が原因/有効だと考えるか
2. Action     (実行)  — 何を実際にやったか
3. Verification (検証) — どう確認したか。**実行コマンドと出力が必須**
4. Decision   (判断)  — 続行 / 方針変更 / 完了 / 中断

### 鉄則
- Verification が空のイテレーションは記録できない。
  「たぶん直った」は反復ではない。
- 各反復は前の反復の Verification に基づいて Hypothesis を更新する。
  同じ Hypothesis を検証なしに繰り返すのは反復ではなく停滞である。
- 上限 (既定 10) に達したら、未達でも理由を記録して人間に返す。

### 使うべき場面
- 「既存システムを調査して改善案を作り、PoC まで進める」
- 原因不明の障害調査
- 性能改善 (測定→仮説→変更→再測定)

### 使うべきでない場面
- 手順が既知で一発で終わる作業
- 検証手段が存在しない作業 (まず検証手段を作る)
GUIDE
}
