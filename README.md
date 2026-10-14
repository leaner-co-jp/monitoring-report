# monitoring-report

各プロダクトチームのインフラモニタリング会（通称「モニ会」）で使う週次レポートのテンプレートと、生成に必要な運用知識を管理する。

対象プロダクトは3つある。
**LP** はリーナー見積、**PU** はリーナー購買、**FJ** はリーナーコネクトを指す。

## リポジトリの構成

レポートは3つの層を合成して生成する。

- **[`skills/weekly-infra-report/`](skills/weekly-infra-report/)**：3プロダクト共通の生成手順。「LP の週次レポートを生成して」と依頼するときに、Codex などのエージェントが参照するスキル。
- **[`templates/report.md`](templates/report.md)**：共通レポートテンプレート。🔗 調査リンク、§1 総合評価、§2 調査、§3 付録からなる。
- **[`templates/lp.md`](templates/lp.md) / [`pu.md`](templates/pu.md) / [`fj.md`](templates/fj.md)**：プロダクト固有値。共通側の `{{P.xxx}}`（変数）と `{{P:xxx}}`（ブロック）に差し込む。
- **[`bin/weekly-report`](bin/weekly-report) / [`lib/weekly_report/`](lib/weekly_report/)**：レポートを機械的に組み立てて検証する Ruby スクリプト。エージェントは値と所見を JSON に書くだけで、構成・固定文・書式はスクリプトが決める（理由は [docs/workflow.md](docs/workflow.md#なぜ本文をスクリプトで組むのか)）。
- **[`docs/`](docs/)**：運用上の知識と落とし穴。全体像は [docs/overview.md](docs/overview.md)、生成手順の概要は [docs/workflow.md](docs/workflow.md) にある。

生成したレポートの出力先は Notion のプロダクト別データベースである。
その URL、データソース ID、タイトルプロパティ名は `templates/<product>.md` の変数表にある。

## レポート作成手順

> 手順の正本は [`skills/weekly-infra-report/SKILL.md`](skills/weekly-infra-report/SKILL.md) である。
> この節は、人が実行するときの流れをまとめたものにすぎない。
> 記述が食い違う場合はスキル側を正とし、この節を修正する。

### 1. 生成できる週か確認する

対象は直近のクローズ済みの7日間である。
週クローズ前（partial-window）に生成すると、リクエスト数やジョブ件数、ALB カウントといった累積系メトリクスを過少に計上してしまう。
週の途中では生成しない。

| チーム | 対象ウインドウ | 生成タイミング |
| --- | --- | --- |
| LP | 水曜 00:00 〜 火曜 23:59 JST | 水曜 09:00 JST |
| PU / FJ | 金曜 00:00 〜 木曜 23:59 JST | 金曜 09:05 JST |

通常はスケジュールタスク（cron）が自動実行する。
手動で実行するのは、自動実行が失敗した週、過去週の未作成分を補う週、手順を変更して検証する週である。

### 2. エージェントに依頼する

リポジトリのルートで、対象プロダクトを指定して依頼する。

```
LP の週次レポートを生成して
```

エージェントは `skills/weekly-infra-report/SKILL.md` を起点に、`templates/<lp|pu|fj>.md` の固有値を読み込んで進める。

⚠️ このスキルは、特定のエージェントに依存しないようリポジトリ直下の `skills/` に置いている。
Claude Code のプロジェクトスキル自動検出は `.claude/skills/` だけを対象とするため、自動検出に頼る環境では `skills/weekly-infra-report/SKILL.md` を読むよう明示する。

### 3. エージェントが進める流れ

```
0. bin/weekly-report window で対象ウインドウとタイトルを確定（閉じていない週はエラー）
1. 出力先 DB を作成日時 DESC で確認 → 同名ページがあれば中止
2. bin/weekly-report stub で入力 JSON の雛形を作る
3. monitor 状態を一括取得（Observe の主軸）
4. アラート発火イベントを収集（今週・先週）
5. SLO の数値を取得
6. アプリ調査トリガを判定
   └ ON なら発火ウインドウに絞って深掘り（OFF の週は調査手順を読まない）
7. インフラ指標の週次値を取得（先週比トレンド用）
8. 前週レポートを参照（先週比の引用・前回 Decide / Act の反映状況）
   （3〜8 の値と所見は入力 JSON に書き込む）
9. bin/weekly-report render で完成形を組み立てて検証
10. render が出した Notion 用の本文をそのままページにする
```

**同名ページがすでにあれば新規作成しない。**
その場合は findings だけを報告して終了する。
重複判定はページタイトルの一致に依存するため、タイトルの固定部分は変更しない。

### 4. 出力前の検証

`bin/weekly-report render` が、完成形を組み立てたあとに次を機械的に検証する。1つでも外れたら全件を列挙して失敗し、Notion 用の本文を書き出さない（一覧は [`references/output.md`](skills/weekly-infra-report/references/output.md#検証render-が機械的に確かめること)）。

- ページタイトルが固定形式で、期間が対象ウインドウの7日間になっている
- 見出しの並び・固定文・台帳の行がテンプレートと一致している
- monitor の発火に色を付けていない（件数と継続時間で書いている）
- 台帳に発火があれば §2 があり、発火がない週は §2 が存在しない
- 総合ステータスと §2 の色が max ルールを満たしている
- 取得できなかった箇所に `⚠️ 取得不可: <理由>` と理由が書かれている

Claude Code では、レポート DB への書き込みを render が検証した本文だけに制限する hook（`.claude/settings.json`）も効く。
人がレビューするときは、render が見ない判断の部分（総合ステータスの判定理由、monitor 以外で動いた指標、前回 Decide / Act の反映状況）を見る。

既存のページを手で直したときは、直した Markdown を `bin/weekly-report validate <file>` にかける。

### 5. うまくいかないとき

| 症状 | 確認先 |
| --- | --- |
| メトリクスの数値が閾値と合わない | [docs/datadog-mcp-tips.md](docs/datadog-mcp-tips.md)。vCPU 正規化、`.rollup(avg, 3600)`、scalar dedup の罠がまとめてある |
| FJ の monitor が0件になる | team タグは `connect` であって `fj` ではない |
| 応答上限を超えて生成が止まる | `references/collect.md` の「取得の原則」と「取得順と失敗時の代替」 |
| 固定値（SLO ID やサービス名）が違う | `templates/<product>.md` の変数表と `{{P:targets}}` |

## スクリプトの開発

Ruby 3.3 以上で動き（3.3 / 4.0 で確認）、標準ライブラリ以外に依存しない。テストは minitest。

```bash
rake test                 # すべてのテスト
ruby -Ilib test/renderer_test.rb
```

テンプレート（`templates/*.md`）を直したら `rake test` を流す。テストはテンプレートから入力 JSON の雛形を作り、3プロダクトとも描画と検証が通ることを確かめるので、スロットや表の行の書き損じはここで見つかる。

## テンプレートを直すとき

| 直したいもの | 直す場所 |
| --- | --- |
| 取得手順、評価ルール、出力ルール（3プロダクト共通） | `skills/weekly-infra-report/references/` |
| レポートの節構成とスロット（差し込み記法は `templates/report.md` 冒頭の運用ガイド） | `templates/report.md` |
| 合成・描画・検証のロジック | `lib/weekly_report/`（直したら `rake test`） |
| プロダクト固有の値、閾値、monitor 一覧、台帳の行 | `templates/<lp\|pu\|fj>.md` |
| 閾値そのもの | `leaner-terraform` の `environments/datadog/` |

**判定の材料は monitor の発火とその波及だけである。**
エージェントが独自に閾値を持ち出して判定するわけにはいかない。
閾値が必要になったら、レポート側で判定を足すのではなく Datadog monitor を作る。
この方式を選んだ経緯は [docs/overview.md](docs/overview.md#なぜこの方式にしたか) にある。
