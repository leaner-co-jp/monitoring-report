# Datadog MCP の落とし穴

**メトリクスを取得する前に必読。** ここに書いてある罠はどれも「エラーにならないまま間違った数値がレポートに載る」タイプで、閾値評価を狂わせる。

## 使うツール

| ツール | 用途 |
| --- | --- |
| `search_datadog_monitors` | monitor 状態の一括取得（Observe の主軸） |
| `search_datadog_events` | アラートの発火・復旧イベントを時系列で取得 |
| `aggregate_events` | アラートの件数・概況を軽量に集計（本文が不要なとき） |
| `get_datadog_metric` | メトリクスクエリ。**先週比トレンドの補足取得のみ**に使う |
| `get_datadog_dashboard` | ダッシュボード構成・ウィジェット値（SLO 数値の取得元） |
| `get_datadog_metric_context` | メトリクスのタグ／メタデータ探索（必要時のみ） |
| `search_datadog_spans` | 個々のスパンを duration 降順で直接列挙（外れ値検知） |
| `get_datadog_trace` | trace_id からトレース全体の waterfall を取得し支配スパンを特定 |
| `aggregate_spans` | スパンの集計（ただし後述の癖あり） |

全呼び出しで `telemetry.intent`（英語・短く・値や PII を含めない）を必須指定。

## 期間の渡し方

`from` / `to` に直接渡す。ISO 8601（`2026-07-22T00:00:00+09:00`）・Unix 秒・相対表記（`now-1d`）のいずれも可。**今週と先週は別々に取得して比較する**（1回のクエリで両方は取れない）。

調査リンクの `from_ts` / `to_ts` は **epoch ms**。メトリクスクエリの `from` / `to` が Unix 秒なので取り違えやすい。

---

## 罠 1: scalar dedup（avg と max が区別できなくなる）

`response_format="scalar"` で**同一クエリ文字列**を `aggregator` 違いで複数渡すと、**結果が1つに統合され avg と max を区別できなくなる**。

`scalar` は「期間内を1値に集約」する出力で、集約方法は各クエリオブジェクトの `aggregator`（`avg` / `sum` / `min` / `max` / `last`）で決まる。クエリ接頭辞の `p50:` 等とは別物。

**回避策（どちらか）**:

- (a) 別々の `get_datadog_metric` コールに分ける
- (b) `timeseries` で取得して自前で avg / max を算出する

## 罠 2: ECS CPU % の vCPU 正規化

生の `ecs.fargate.cpu.percent` は**単一 vCPU 基準**。複数 vCPU 割当のタスク（API 等）では 100% を超えた値が返り、閾値（90 / 95）と直接比較すると誤読する。

**monitor と同じ正規化式を使う**:

```
max:ecs.fargate.cpu.percent{ecs_service:<svc>}.rollup(avg, 3600)
  / ( max:ecs.fargate.cpu.task.limit{ecs_service:<svc>} / 1000000000 )
```

## 罠 3: 素の `aggregator="max"` は瞬間生値ピークを拾う

`.rollup()` なしの `aggregator="max"` は**1分粒度の瞬間生値ピーク**を返す。実測例: LP API CPU 197%、RDS Writer CPU 99%、FJ API CPU 84% / 101%。これらは閾値（ECS 90 / 95、RDS 75 / 90）と整合しない**アーティファクト**であり、閾値評価に使ってはいけない。

**週内の「持続的なピーク」を評価したいなら、必ず `.rollup(avg, 3600)` をクエリ文字列に埋める**（= 1時間平均の週内最大）。

対象: ECS の CPU / メモリ、RDS の CPU / コネクション。

### ECS メモリ %

```
max:ecs.fargate.mem.rss{ecs_service:<svc>}.rollup(avg, 3600)
  / max:ecs.fargate.mem.task.limit{ecs_service:<svc>}.rollup(avg, 3600) * 100
```
`aggregator="max"` で取得。

### RDS

タグ: `{env:production, dbclusteridentifier:<cluster>, role:<writer|reader>}`

- `aws.rds.cpuutilization`（max / avg）— max は `.rollup(avg, 3600)` 必須
- `aws.rds.database_connections`（max / avg）— max は `.rollup(avg, 3600)` 必須
- `aws.rds.freeable_memory`（avg）
- `aws.rds.read_iops` / `aws.rds.write_iops`（avg）

### ALB

タグ: `{service:<api-service>, env:production}`

- `httpcode_target_2xx` + `httpcode_elb_3xx` / `elb_4xx` / `elb_5xx` — `aggregator="sum"`, `.as_count()`
- `healthy_host_count` / `un_healthy_host_count` — `aggregator="avg"`

## 罠 4: レイテンシ系メトリクスの単位

`trace.*` は**秒単位**。ms 表記にするには ×1000。忘れると3桁ずれる。

## 罠 5: RDS IOPS の `.as_count()` 自動適用

`aws.rds.read_iops` / `write_iops` は rate メトリクスで `.as_count()` が自動適用される。**週合計の絶対値は参考値にすぎない。先週比のトレンドのみ評価する。**

## 罠 6: `/apm/traces` は広い `start` を無視する

`/apm/traces` は `storage=hot` のため、**広い `start` を無視して end − 15分にクランプ**する。

- 週レンジを見せたい → **ダッシュボードリンクを使う**（`/dashboard/<id>?from_ts={{F}}&to_ts={{T}}`, epoch ms）
- 特定インシデント時刻の点的な調査 → `/apm/traces?...&end={{incident_epoch_ms}}&paused=true`（15分ウインドウ、`paused=true` でウインドウ固定）
- 週全体で重い endpoint / resource を順位付け → APM サービスページ（`/apm/services/<service>?env=production&start={{F}}&end={{T}}`）

## 罠 7: `aggregate_spans` の `group_by` が 0 buckets を返す

`MAX(duration) by {service, resource_name}` のような `group_by` 付きの集計は **0 buckets を返すことがある**（facet 化の癖。events の `group_by` と同様）。

**最悪スパンの特定は `search_datadog_spans` の duration 降順を主軸にする**:

```
search_datadog_spans  query="env:production @duration:>30000000000"  sort="-@duration"
```

`@duration` は **ns 単位**（30000000000 = 30秒）。閾値は状況に応じて調整。

root（`rack.request`）だけでなく DB クライアント層（LP なら `service:trilogy` / `operation_name:trilogy.query`）まで見る。`rails.db.runtime` が大きければ DB 起因。支配スパンの特定は `get_datadog_trace(trace_id)` の waterfall で。

## 罠 8: p50 / avg は単発の外れ値を平滑化して消す

60秒級の重い SQL のような**単発の長時間トレース**は p50 / avg 集約では見えなくなる。メトリクスで見るなら p50 ではなく `max` / p99 を使い、実スパンを見るなら罠 7 の duration 降順検索を使う。

RDS Writer CPU / コネクションの critical 調査では、duration 降順検索で「その時刻に Writer 宛（`peer.hostname` が `<cluster>.cluster-…`）に出ていた重い SQL」を特定し、**悪化の主体を『実際に DB を叩いた endpoint / SQL』に置く**。同ウインドウに居るだけのジョブを主体と断定しない（p50 集約だけの相関による当て推量を避ける）。

## 罠 9: monitor / event 応答のページング

`search_datadog_monitors` は応答が truncate される。`is_truncated` が立っていたら `start_at` を進めて全件取る。**取り漏らすと「発火していない」と誤報告する。**

## 罠 10: SLO の数値は MCP で直接取れない

monitor は SLO の「状態」（枯渇・急消費の有無）しか返さない。**SLI % とエラーバジェット残 % の数値を返す専用ツールがない**ため、`get_datadog_dashboard` でダッシュボードの SLO ウィジェット値を参照する。取得できなければ `⚠️ 取得不可: <理由>` と明記する（省略禁止）。

## 罠 11: ダッシュボードのフル取得は重い

`get_datadog_dashboard` のフル取得は LP で約 18k トークン、**FJ は約 61k 文字で MCP 応答上限を超える**。構成差分の検知（プロンプト §0.4 手順6）は毎回やらず、必要な widget に絞る。

---

## トークン節約の指針

- monitor 状態は**1コールで一括取得**（`include_tags=["*"]`）。
- 件数や概況だけなら `search_datadog_events` ではなく `aggregate_events`。発火ウインドウの正確な epoch が必要になったときだけ `search_datadog_events` を絞って使う。
- ダッシュボードのフル取得は避ける。
- トリガ OFF の週は詳細トレース調査をスキップする（これが最大の節約）。
- `get_datadog_metric` の応答に付いてくる `metrics_explorer_url` と、アラートイベント本文の埋め込みリンクは **Datadog 生成なので再利用が最も安全**。手組み URL より優先する。
