# 📌 SOURCE OF TRUTH

このプロジェクトで「事実」とみなす情報の所在を定義する。
矛盾したときは、この優先順位で解決する。

## 優先順位

| 優先 | 対象 | 意味 |
|---|---|---|
| 1 | 実行時の実測値 | `./start.sh doctor` などの出力。最も強い |
| 2 | 実インストール済みのファイル | `~/.omh/skills`, `~/.hermes/plugins/omh` 等の実在 |
| 3 | `state.json` | 検証済み事実の記録。`class` で根拠の強さを明示 |
| 4 | `config/omh-capability-catalog.json` | 出荷時スナップショット。実測が無いときのみ使う |
| 5 | upstream ドキュメント | 仕様の一次情報。ただしバージョンで変わる |
| 6 | 本 README / docs | 説明。実測に劣る |

## 絶対規則

1. **未確認を確認済みとして書かない。**
   `state.json` の `class` は `OBSERVED` / `SNAPSHOT` / `UNVERIFIED` のいずれかとし、
   根拠 (`how`) を添える。

2. **公開ページの掲載値を事実として採用しない。**
   OMH の公開ページは 116 skills / 9 workflows / 7 families / 8 languages を
   掲げているが、実インストール後の実測は 123 skills / 9 役割 / 6 families である
   （実レイアウト: `~/.omh/skills/<役割>/<スキル名>/SKILL.md`）。
   本ツールは実測を表示し、差がある場合は両方を併記する。

3. **実測が無いときは「実測に基づく」と言わない。**
   `./start.sh evidence check` がこれを機械的に検査する。
   観測 0 件なら合格を返さない。

4. **dry-run は「完了」と言わない。**
   未実行であることを明示する。回帰テストで担保している。

## 検証コマンド

```bash
./start.sh doctor            # 統合診断 (実測)
./start.sh doctor --quick    # 上流 omh doctor を呼ばずに高速診断
./start.sh evidence check    # 本ツール自身の主張の検証
./start.sh skills summary    # カタログ件数とデータ源
npm test                     # bats 全件
npm run lint                 # shellcheck
```
