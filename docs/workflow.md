# レポート生成の手順

正式な手順定義は agent 非依存の **skill** [`skills/weekly-infra-report/`](../skills/weekly-infra-report/)。ここはそれを俯瞰し、**手順の意図と失敗しやすい箇所**を補うもの。

## どのファイルに何があるか

レポートは**3つの層の合成**で生成される。共通側の `{{P.xxx}}`（変数）と `{{P:xxx}}`（ブロック）に、`templates/<product>.md` の値が差し込まれる。**合成と本文の組み立て・検証は `bin/weekly-report`（Ruby）がやり、エージェントは入力 JSON に値と所見を書くだけ**（下の「なぜ本文をスクリプトで組むのか」）。

| ファイル | 中身 | いつ読まれるか |
| --- | --- | --- |
| `SKILL.md` | ゴール（OODA）・絶対に守ること・読み込み順・ウインドウ・重複防止・ページタイトル | 常に（最初） |
| `templates/<lp\|pu\|fj>.md` | 変数表と11の差し込みブロック | 常に（最初） |
| `references/collect.md` | 取得の原則 / 取得順と失敗時の代替 / 手順1（monitor）・2（アラート）・3（SLO）・4-a（トリガ判定）・6（ダッシュボード）/ 前週レポートの参照 | 手順1〜3 |
| `references/metrics.md` | 手順5 の共通クエリ式（ECS の vCPU 正規化・`.rollup(avg, 3600)`・RDS・ALB） | 手順5 |
| `references/investigate.md` | 手順4-c（トレース調査）・4-d（相関調査プレイブック） | **トリガ ON の週だけ** |
| `references/evaluate.md` | 色の意味・総合ステータスの判定順序・severity の扱い・閾値 | 色を付けるとき |
| `references/output.md` | 出力ルール・入力 JSON の書き方・調査リンク規約・日本語表現・render が検証すること | 入力 JSON を埋めるとき |
| `templates/report.md` | レポート本体（§1 総合評価 / §2 調査 / §3 付録）のスロットと、各スロットの「ガイド:」 | 入力 JSON を埋めるとき（`render` も読む） |
| `bin/weekly-report` / `lib/weekly_report/` | ウインドウ計算・合成・入力 JSON の雛形・描画・検証・Notion 形式への変換・書き込みガード | 毎回（エージェントが実行する） |

`templates/<product>.md` の差し込みブロック:

| ブロック | 差し込み先 |
| --- | --- |
| `targets` | collect.md 冒頭（SLO ID・ECS サービス名・RDS・ALB タグ・ダッシュボード） |
| `monitors` | collect.md 手順1（monitor の本数・内訳・ID・monitor 不在リソース） |
| `known-issues` | collect.md 手順6（ダッシュボード固有の既知事項） |
| `metric-queries` | metrics.md 手順5（このプロダクトで取る対象） |
| `thresholds` | evaluate.md（閾値表と固有注記） |
| `domain-notes` / `playbook-notes` | investigate.md（調査時のみ） |
| `ledger` | report.md §3.1（台帳の表と脚注） |
| `investigation-premises` | report.md §2 冒頭（調査時の前提） |
| `signal-rows` / `signal-guide-note` | report.md §1（先週比の主要変化の行・ガイド注記） |

## 全体の流れ

```
0. `bin/weekly-report window` で対象ウインドウ・タイトルを確定（クローズ済みでなければエラー）
1. 出力先 DB を作成日時 DESC で確認 → 同名ページがあれば中止
2. `templates/<product>.md` を読み、`bin/weekly-report stub` で入力 JSON を作る
3. monitor 状態を一括取得（Observe の主軸）
4. アラート発火イベントを収集（今週・先週）
5. SLO の対象週・先週の数値を Status API で取得
6. アプリ調査トリガを判定 → ON なら発火ウインドウに絞って深掘り
7. インフラ指標の週次値を取得（先週比トレンド用）
8. 前週レポートを参照（先週比の引用・前回 Decide/Act の反映状況）
9. `bin/weekly-report render` で完成形を作って検証（失敗したら入力 JSON を直して再実行）
10. render が出した `.notion.md` をそのまま出力先 Notion DB にページ作成
```

## 0. 対象ウインドウの確定

LP は水曜〜火曜、PU・FJ は金曜〜木曜。**直近のクローズ済みの週**を取る。

ウインドウ・タイトル・タイムスタンプは `bin/weekly-report window` が出す。**自分で計算しない**（以前は python のワンライナーを手で書き換えていたが、日付の打ち間違いや UTC ずれがウインドウ全体を壊す）:

```bash
bin/weekly-report window --product lp                    # 直近のクローズ済みの週
bin/weekly-report window --product pu --end 2026-10-08   # 過去週の補完
```

終端曜日でない日付や、まだ閉じていない週（partial-window）を指定するとエラーになる。`window.from_s` / `to_s` は今週の Unix 秒、`*_ms` は epoch ms（調査リンクの `from_ts` / `to_ts` 用）。

## 1. 重複防止（作成より先にやる）

出力先 DB を作成日時の降順で確認し、対象ウインドウの同名ページが既にあれば**新規作成しない**。その場合は findings のみを報告して終わる。

SQL で確認する例（データソース ID は [notion-sources.md](notion-sources.md)）:

```sql
SELECT "ドキュメント名", "作成日時" FROM "collection://..." ORDER BY datetime("作成日時") DESC LIMIT 3
```

タイトルプロパティ名がチームで違う（LP・FJ は `ドキュメント名`、PU は `名前`）ので注意。

## 3. monitor 状態の一括取得

```
search_datadog_monitors  query="tag:report:weekly team:<lp|pu|connect>"  include_tags=["*"]
```

1コールで済ませる。**status は色に写さない**（色は「読者への要求」専用 → [monitors.md](monitors.md#評価ステータスのルール)）。事実として記録する:

| monitor status | レポート表記 |
| --- | --- |
| `Alert` / `Warn` | 現在発火中（severity をそのまま書く） |
| `OK` | 現在発火なし（対象ウインドウ中の発火なし、ではない） |
| `No Data` | `⚠️ 取得不可: <理由>` |

⚠️ **monitor は直近10分など短いウインドウで評価する**ので、現在の `status` だけでは週中に発生して復旧済みの一過性シグナルを取りこぼす。週次の傾向は手順4（アラートイベント）と手順7（トレンド）で補う。

⚠️ 応答はページングされる。`is_truncated` が立っていたら `start_at` を進めて全件取る。**取り漏らすと「発火していない」と誤報告する**。

## 4. アラートシグナルの収集

今週・先週を**別々に**、まず `aggregate_events` の `group_by` なし COUNT で総件数を取る。monitor ごとの grouping は任意で、bucket 合計が総件数と一致した場合だけ候補の絞り込みに使う。`@monitor_name` などの grouping が 0 buckets でも、イベント0件とは判定しない。

総件数が1件以上で grouping が空または不完全なら、手順3の全 monitor ID（未対応なら名前）を列挙し、monitor ごとの `search_datadog_events` で Triggered を探す。候補日・時間帯が分かれば狭め、分からなくても「1 monitor × 1対象ウインドウ」に限定して、team 全体の週次本文は取得しない。

対象 monitor では Warn / Triggered / Recovered を別々に記録する。UTC と JST（UTC+9）の変換および対象ウインドウとの境界を検算し、発火から復旧までの時間を算出する。今週の Triggered が手順6のアプリ調査トリガを ON にする。

深刻度ごとの扱い:

- **warning**: 閾値接近の予兆。変化として記録し、複数週続けば傾向として Orient に書く。
- **critical**: 単独報告で終わらせず、**手順6のトリガを ON にして発火ウインドウに絞って原因の主体と上流を掘り下げる**。

## 5. SLO 数値の補完

`execute_code` から Datadog SDK の `v2.ServiceLevelObjectivesApi.getSloStatus`（`GET /api/v2/slo/{slo_id}/status`）を使う。各 SLO ID に対し、レポートと同じ対象週・先週の7日間を `fromTs` / `toTs`（epoch 秒）で別々に指定する。current / 30d の検索 status やダッシュボード値で、過去週の値を代用しない。詳細なフィールド、SDK 例、Bad events の扱いは `references/collect.md` 手順3を正とする。

一部の値を取得できなければ、そのフィールドだけ `⚠️ 取得不可: <理由>` と明記し、SLO monitor の状態・イベントを発火事実としてレポート生成を続ける。

## 6. アプリ調査トリガの判定（必須・毎週）

以下のいずれかが今週該当すれば **ON**:

- 今週の Triggered をイベントで確認（現在の monitor status だけでは対象ウインドウ中の発火有無を判定しない）
- SLO が劣化（エラーバジェット消費の進行・バーンレート警報・SLI 低下）

判定結果（ON / OFF、根拠の monitor / event / SLO、ウインドウの epoch ms）を **§1 の「アプリ調査トリガ」**に必ず書く（3プロダクト共通）。

- **OFF の週**: **§2（調査）を見出しごと出力しない**（「該当なし」の見出しすら出さない）。§1 の「アプリ調査トリガ」に OFF と「インフラ / SLO 異常なし」を書く。数値は手順7で取得して **§3.1 の台帳に記録**する（詳細調査はしない）。Rails レイテンシの恒常ドリフトを SLO と Sentry に委譲する旨は §3.3 に書いてよい。
- **ON の週**: インシデントの**時間ウインドウに絞って**調査する。ウインドウの `from` / `to` を全クエリに渡す。critical があればそれを最優先。

### critical 発火時の相関調査

発火した monitor を単独で見ない。**発火種別ごとに隣接リソースまで同一ウインドウで広げ、「悪化の主体」と「上流原因」を切り分ける**。対応表は `references/investigate.md` 手順4-d（プロダクト固有の行は `{{P:playbook-notes}}`）。

因果は両方向あり得る（DB が遅い → API CPU が上がる／ジョブが重い → Worker メモリが膨らむ）。複数の monitor が同時刻に鳴っていれば同一インシデントの別側面である可能性が高いので、束ねて1つの原因仮説にまとめる。

### 個々の遅いトレース／SQL の検知（LP のテンプレートにのみ明記）

p50 / avg は単発の長時間トレース（60秒級の重い SQL など）を平滑化して見落とす。RDS Writer CPU や ECS の critical / warning ウインドウでは `search_datadog_spans` を `sort="-@duration"` で引いて**個々の遅いスパンを直接列挙**する。root（`rack.request`）だけでなく DB クライアント層（`service:trilogy` / `operation_name:trilogy.query`）まで見る。支配スパンの特定は `get_datadog_trace(trace_id)` の waterfall で行う。

## 7. インフラ指標の週次値

**発火の事実は手順3・4の monitor から取る**（色は付けない → [monitors.md](monitors.md#評価ステータスのルール)）。ここで取るのは先週比の数値と方向を添えるためだけ。

取得するクエリの正確な形と落とし穴（vCPU 正規化・`.rollup(avg, 3600)`・scalar dedup）は **[datadog-mcp-tips.md](datadog-mcp-tips.md) を必ず読む**。ここを間違えると閾値と整合しない数値がレポートに載る。

## 8. 前週レポートの参照

出力先 DB を作成日時の降順で取得し、最新ページを参照する。レポートには次の2つを明記する:

- 先週比セクションへの引用
- **前回の Decide / Act 候補が今週どう反映されたか**

未検出なら「初回扱い」と明記し、ダッシュボード内の calendar_shift データだけを使う。

## 9. 出力

1. `bin/weekly-report render tmp/weekly-report/<product>.json` を実行する。完成形を組み立て、検証し、`tmp/weekly-report/<product>-<YYYYMMDD>.md`（完成形）と `.notion.md`（Notion 用の本文）を書き出す。
2. 失敗したら、列挙されたエラーを入力 JSON 側で直して再実行する（何を検証しているかは [`references/output.md`](../skills/weekly-infra-report/references/output.md)）。
3. 成功したら `.notion.md` の中身をそのまま `content` に、出力の `title` をタイトルプロパティに入れてページを作成する。

除外するもの（運用ガイド・「ガイド:」・説明文）と残すもの（調査時の前提・台帳の注記などのドメイン文脈）の振り分けは render がやる。

## なぜ本文をスクリプトで組むのか

テンプレートを読ませて「この構成どおりに書いて」と指示する方式では、どれだけ強く指示しても出力が週ごとに揺れた。2026-10 時点で LP の自動実行が出したレポートには、次の崩れが混在していた:

- タイトルの形式が変わる（`… 週次レポート 2026/10/07〜10/13`。重複防止の同名判定が効かなくなる）
- 固定文の「色の意味」が言い換えられ、「評価ルール」が丸ごと落ちる
- 台帳の行が統合・省略され、テンプレートにない「§4 収集記録」が足される
- 総合ステータスに 🟡 が使われ、monitor 発火の列に「warning 6回（各10分）」のような独自書式が入る

エージェントは「構成を写す」「値を集めて解釈する」を同時にやっており、前者は本来毎回同じ結果になるべき機械的な作業だった。そこで機械的な部分（ウインドウ計算・合成・固定文・節番号・§2 の有無・Notion 形式）を `bin/weekly-report` に移し、エージェントには値と所見だけを JSON で書かせる。JSON の雛形もテンプレートから生成するので、テンプレートを直せば雛形・描画・検証がすべて追従する。

さらに Claude Code では、`.claude/settings.json` の PreToolUse hook（`bin/weekly-report guard`）が、レポート DB への `notion-create-pages`（とレポート本文の全置換）を **render が検証した本文と一致するものだけ**に制限する。render は検証を通った本文のハッシュを `tmp/weekly-report/approved/` に記録し、hook はそれと照合する（空行と行末の空白は無視）。手で組んだ本文や、検証後に書き換えた本文は書き込めない。

hook は Claude Code 固有の仕組みなので、Codex など他のエージェントでは render の検証までが保証範囲になる。

### ページタイトル（固定形式・変更禁止）

```
YYYY/MM/DD - MM/DD リーナー見積インフラモニタリング 週次レポート
YYYY/MM/DD - MM/DD リーナー購買インフラモニタリング 週次レポート
YYYY/MM/DD - MM/DD リーナーコネクトインフラモニタリング 週次レポート
```

可変部は `YYYY/MM/DD - MM/DD` だけ。固定部はスペース・全角文字を含めて変更しない（重複防止の同名判定がタイトル一致に依存している）。
