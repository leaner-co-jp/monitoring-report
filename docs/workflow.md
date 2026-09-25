# レポート生成の手順

正式な手順定義は agent 非依存の **skill** [`skills/weekly-infra-report/`](../skills/weekly-infra-report/)。ここはそれを俯瞰し、**手順の意図と失敗しやすい箇所**を補うもの。

## どのファイルに何があるか

レポートは**3つの層の合成**で生成される。共通側の `{{P.xxx}}`（変数）と `{{P:xxx}}`（ブロック）に、`templates/<product>.md` の値が差し込まれる。

| ファイル | 中身 | いつ読まれるか |
| --- | --- | --- |
| `SKILL.md` | ゴール（OODA）・絶対に守ること・読み込み順・ウインドウ・重複防止・ページタイトル | 常に（最初） |
| `templates/<lp\|pu\|fj>.md` | 変数表と11の差し込みブロック | 常に（最初） |
| `references/collect.md` | 取得の原則 / 取得順と失敗時の代替 / 手順1（monitor）・2（アラート）・3（SLO）・4-a（トリガ判定）・6（ダッシュボード）/ 前週レポートの参照 | 手順1〜3 |
| `references/metrics.md` | 手順5 の共通クエリ式（ECS の vCPU 正規化・`.rollup(avg, 3600)`・RDS・ALB） | 手順5 |
| `references/investigate.md` | 手順4-c（トレース調査）・4-d（相関調査プレイブック） | **トリガ ON の週だけ** |
| `references/evaluate.md` | 色の意味・総合ステータスの判定順序・severity の扱い・閾値 | 色を付けるとき |
| `references/output.md` | 出力ルール・除外するもの・調査リンク規約・日本語表現・書き込み前の検証チェック | 書き始めるとき |
| `templates/report.md` | レポート本体（§1 総合評価 / §2 調査 / §3 付録）と運用ガイドのトグル | 書き始めるとき |

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
0. 対象ウインドウを確定（クローズ済みか確認）
1. 出力先 DB を作成日時 DESC で確認 → 同名ページがあれば中止
2. `templates/<product>.md` を読む（変数とブロックの供給元）
3. monitor 状態を一括取得（Observe の主軸）
4. アラート発火イベントを収集（今週・先週）
5. SLO の対象週・先週の数値を Status API で取得
6. アプリ調査トリガを判定 → ON なら発火ウインドウに絞って深掘り
7. インフラ指標の週次値を取得（先週比トレンド用）
8. 前週レポートを参照（先週比の引用・前回 Decide/Act の反映状況）
9. `output.md` の検証チェックを通し、`templates/report.md` の構成に沿って埋めて出力先 Notion DB にページ作成
```

## 0. 対象ウインドウの確定

LP は水曜〜火曜、PU・FJ は金曜〜木曜。**直近のクローズ済みの週**を取る。

Unix timestamp の算出（`SKILL.md`「ウインドウ」に載っているワンライナー）:

```bash
python3 -c "import datetime as dt, zoneinfo as zi; jst=zi.ZoneInfo('Asia/Tokyo'); s=dt.datetime(2026,7,22,0,0,tzinfo=jst); e=dt.datetime(2026,7,28,23,59,59,tzinfo=jst); print('F=',int(s.timestamp())); print('T=',int(e.timestamp())); print('PF=',int((s-dt.timedelta(days=7)).timestamp())); print('PT=',int((e-dt.timedelta(days=7)).timestamp()))"
```

`F` / `T` は今週、`PF` / `PT` は先週。調査リンクの `from_ts` / `to_ts` は **epoch ms**（秒を1000倍）なので取り違えないこと。

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

**書き込む前に `references/output.md` の検証チェックを全項目通す**（プレースホルダの残留・ウインドウ・重複・§1〜§3 構成・発火ゼロ週の §2 非出力・色の使い方・台帳の校正メモ・取得不可の理由・前回 Decide / Act の反映状況）。満たさない項目は書き込む前に直し、直せないものは §3.3 に理由を書く。

そのうえでテンプレート部の構成に沿ってプレースホルダを埋め、出力先 Notion DB に新規ページを作成する。

**出力時に必ず除外するもの**:

1. `templates/report.md` 冒頭の運用ガイド（トグル）
2. テンプレートの methodology 前置き（「monitor 駆動の OODA レポート…」等の枕文）
3. 「ガイド:」で始まる記入指示、書き方だけを指示する注記

**残すもの**: ドメイン文脈を伝える注記は中身なので残す。Sentry 棲み分けと IOPS 注意（§2 冒頭の「調査時の前提」と §3.1 の注記）、FJ の elb 防御シグナルなど。

出力の開始位置はタイトル行（`# …`）から。前置きの引用文は付けず、そのまま `## 1` へ続ける。

### ページタイトル（固定形式・変更禁止）

```
YYYY/MM/DD - MM/DD リーナー見積インフラモニタリング 週次レポート
YYYY/MM/DD - MM/DD リーナー購買インフラモニタリング 週次レポート
YYYY/MM/DD - MM/DD リーナーコネクトインフラモニタリング 週次レポート
```

可変部は `YYYY/MM/DD - MM/DD` だけ。固定部はスペース・全角文字を含めて変更しない（重複防止の同名判定がタイトル一致に依存している）。
