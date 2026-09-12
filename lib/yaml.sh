#!/usr/bin/env bash
# ============================================================
# yaml.sh — config.yaml 用の最小 YAML リーダ
#
# 重要 (evidence boundary):
#   Hermes 本体の設定は config.yaml である。一方 yq は標準搭載されて
#   いないため、ここでは「単純な key: value」と「1段のネスト」だけを
#   読む最小パーサを提供する。複雑な YAML (アンカー, 複数行, 配列の
#   フロー記法) は読めない。読めなかった場合は空文字を返し、呼び出し
#   側は既定値で動く。推測で値を捏造しない。
# ============================================================

if [[ -n "${__HERMESOS_YAML_SH:-}" ]]; then
  return 0
fi
__HERMESOS_YAML_SH=1

# yaml_get <file> <dotted.key> [default]
#   例: yaml_get "$HERMES_HOME/config.yaml" "skills.creation_nudge_interval"
#   値のクォートは除去する。コメントは行頭 '#' のみ対応。
#
#   制限 (evidence boundary):
#     複数行の配列 (key:\n  - item) は読めない。その場合は default ではなく
#     番兵値 __YAML_MULTILINE__ を返し、「キーが無い」と「読めない」を
#     区別できるようにする。呼び出し側が誤った既定値を使わないためである。
readonly YAML_MULTILINE_SENTINEL="__YAML_MULTILINE__"

yaml_get() {
  local file="$1" key="$2" default="${3:-}"
  [[ -f "$file" ]] || { printf '%s' "$default"; return 0; }

  local section="" rest="" line indent val cur_section=""
  local want_section="" want_key=""
  local in_array=0

  if [[ "$key" == *.* ]]; then
    want_section="${key%%.*}"
    want_key="${key#*.}"
  else
    want_key="$key"
  fi

  while IFS= read -r line || [[ -n "$line" ]]; do
    # 行頭コメント / 空行を除去
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    [[ -z "${line//[[:space:]]/}" ]] && continue

    # インデント幅を数える
    indent="${line%%[![:space:]]*}"
    rest="${line#"$indent"}"

    # 配列要素の行か? (「- 」で始まる)
    local is_item=0
    [[ "$rest" == "- "* || "$rest" == "-" ]] && is_item=1

    # 配列を読んでいる途中で、インデントが戻ったら配列終了
    if [[ "$in_array" -eq 1 && "$is_item" -eq 0 ]]; then
      # 新しいキー行に到達した
      in_array=0
    fi

    if [[ -z "$want_section" ]]; then
      # トップレベルキーを探す
      if [[ "${#indent}" -eq 0 && "$rest" == "$want_key":* ]]; then
        val="${rest#*:}"
        val="${val#"${val%%[![:space:]]*}"}"
        if [[ -z "$val" ]]; then
          # 値が同一行に無い → 次行が配列の可能性
          in_array=1
          continue
        fi
        printf '%s' "$(_yaml_unquote "$val")"
        return 0
      fi
    else
      if [[ "${#indent}" -eq 0 ]]; then
        cur_section=""
        if [[ "$rest" == "$want_section":* ]]; then
          cur_section="$want_section"
          # インライン値 (skills: {...}) は非対応 → 空
          continue
        fi
      elif [[ -n "$cur_section" && "${#indent}" -gt 0 ]]; then
        if [[ "$rest" == "$want_key":* ]]; then
          val="${rest#*:}"
          val="${val#"${val%%[![:space:]]*}"}"
          if [[ -z "$val" ]]; then
            # ネストした配列 (external_dirs:) は読めない
            printf '%s' "$YAML_MULTILINE_SENTINEL"
            return 0
          fi
          printf '%s' "$(_yaml_unquote "$val")"
          return 0
        fi
      fi
    fi
  done < "$file"

  printf '%s' "$default"
}

# yaml_is_multiline <value> — 番兵値かどうか
yaml_is_multiline() { [[ "$1" == "$YAML_MULTILINE_SENTINEL" ]]; }

# yaml_list_get <file> <dotted.key> — 複数行配列を1行ずつ返す
#   制限付きだが、skills.external_dirs のような単純な配列は読める。
yaml_list_get() {
  local file="$1" key="$2"
  [[ -f "$file" ]] || return 0

  local want_section="" want_key=""
  if [[ "$key" == *.* ]]; then
    want_section="${key%%.*}"; want_key="${key#*.}"
  else
    want_key="$key"
  fi

  local line indent rest cur_section="" collecting=0 base_indent=-1
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    [[ -z "${line//[[:space:]]/}" ]] && continue
    indent="${line%%[![:space:]]*}"
    rest="${line#"$indent"}"

    if [[ "${#indent}" -eq 0 ]]; then
      cur_section=""
      collecting=0
      if [[ -n "$want_section" && "$rest" == "$want_section":* ]]; then
        cur_section="$want_section"
      fi
      continue
    fi

    if [[ "$collecting" -eq 1 ]]; then
      if [[ "$rest" == "- "* ]]; then
        printf '%s\n' "$(_yaml_unquote "${rest#- }")"
        continue
      fi
      collecting=0
    fi

    if [[ -z "$want_section" && "${#indent}" -eq 0 && "$rest" == "$want_key":* ]]; then
      collecting=1; base_indent=${#indent}
    elif [[ -n "$cur_section" && "$rest" == "$want_key":* ]]; then
      collecting=1; base_indent=${#indent}
    fi
    : "$base_indent"
  done < "$file"
}

_yaml_unquote() {
  local v="$1"
  # 末尾コメント除去 (値の後の " #")
  v="${v%%[[:space:]]#*}"
  # 前後空白
  v="${v#"${v%%[![:space:]]*}"}"
  v="${v%"${v##*[![:space:]]}"}"
  # クォート除去
  case "$v" in
    \"*\") v="${v#\"}"; v="${v%\"}" ;;
    \'*\') v="${v#\'}"; v="${v%\'}" ;;
  esac
  printf '%s' "$v"
}

# yaml_has_key <file> <dotted.key>
yaml_has_key() {
  local file="$1" key="$2" sentinel="__HERMESOS_ABSENT__"
  local v
  v="$(yaml_get "$file" "$key" "$sentinel")"
  [[ "$v" != "$sentinel" ]]
}
