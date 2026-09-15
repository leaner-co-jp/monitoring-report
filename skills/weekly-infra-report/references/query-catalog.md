# Datadog クエリカタログ

週次レポートで引くクエリの登録簿である。
**クエリ文字列の正本はここにある。** 手順ファイル（`collect.md` / `investigate.md`）は、このカタログの ID を参照して「なぜ・どう使うか」を書く。

> **このカタログのどのクエリも、単独で対応要否を判定する材料に使わない。**
> 判定の材料は monitor の発火と SLO シグナルだけである（`evaluate.md`）。
> ここで取る数値は、先週比の方向と大きさを添えるためと、§3.1 の台帳に記録するために引く。
> しきい値が必要になったら、カタログに判定条件を足すのではなく Datadog monitor を作る。

取得の区分は2つある。

- **常時**：発火の有無にかかわらず毎週引く。
- **発火時**：アプリ調査トリガが ON の週だけ引く（判定は `collect.md` 手順4-a）。トリガ OFF の週に引くと、誤検知とトークンを生むだけで終わる。

`{{P.xxx}}` はプロダクト固有値に置き換わる（`templates/<product>.md` の変数表）。

## 常時取得

| ID | 目的 | 記載先 | 種別 | クエリ / 取得条件 | 集計・単位 | 欠損時 |
| --- | --- | --- | --- | --- | --- | --- |
| `mon-status` | monitor の現在状態を一括取得（Observe の主軸） | §1 / §3.1 の「monitor発火」列 | monitors | `search_datadog_monitors` に `query="tag:report:weekly team:{{P.team}}"`, `include_tags=["*"]` | 状態語をそのまま事実として記録 | monitor 状態を取得不可とし、`alert-count` の発火件数で Observe を代替 |
| `alert-count` | 今週・先週の monitor 別発火件数 | §1「今週のシグナル変化」 | events | `aggregate_events` に `query="source:alert team:{{P.team}}"`。今週と先週を別々に | 件数 | 手順1 の現在状態だけで書き、週中の一過性発火は取りこぼしとして明記 |
| `alert-window` | 発火した monitor の発火時刻と復旧時刻 | §2 の「シグナル」 | events | `search_datadog_events`。`alert-count` で件数の立った monitor 名と時間帯に絞り、「Triggered」を含むイベントのみ | 発火時刻・継続分数・epoch ms | 「発火ウインドウ取得不可」と明記し、手順4 は日付単位の粗いウインドウで進める |
| `slo-value` | SLI % とエラーバジェット残 % | §1 / §3.1 の SLO 行 | SLO | SLO 専用の取得経路を優先。無ければ SLO ID を限定した `get_datadog_metric`。ID は `collect.md` 冒頭の「対象（プロダクト固定値）」の表にある | % | SLO monitor の状態を事実として採用し、SLI / EBR は `⚠️ 取得不可: <理由>` |
| `ecs-mem` | ECS メモリの持続ピークと平均 | §3.1 台帳 | metrics | `max:ecs.fargate.mem.rss{ecs_service:<svc>}.rollup(avg, 3600)` / `max:ecs.fargate.mem.task.limit{...}.rollup(avg, 3600)` × 100 | `aggregator="max"`（1時間平均の週内最大）と `avg`。% | その行だけ取得不可にする |
| `ecs-cpu` | ECS CPU の持続ピークと平均 | §3.1 台帳 | metrics | `max:ecs.fargate.cpu.percent{ecs_service:<svc>}.rollup(avg, 3600)` / ( `max:ecs.fargate.cpu.task.limit{ecs_service:<svc>}` / 1000000000 ) | `max` と `avg`。vCPU 正規化後の % | 同上 |
| `rds-cpu` | RDS の CPU | §3.1 台帳 | metrics | `aws.rds.cpuutilization{env:production, dbclusteridentifier:{{P.db_cluster}}, role:<role>}`。max を取る側は `.rollup(avg, 3600)` を埋める | `max` と `avg`。% | 同上 |
| `rds-conn` | RDS のコネクション数 | §3.1 台帳 | metrics | `aws.rds.database_connections{...同タグ}`。max を取る側は `.rollup(avg, 3600)` を埋める | `max` と `avg`。件 | 同上 |
| `rds-mem` | RDS の空きメモリ | §3.1 台帳 | metrics | `aws.rds.freeable_memory{...同タグ}` | `avg`。GiB | 同上 |
| `rds-iops` | RDS の読み書き IOPS | §3.1 台帳 | metrics | `aws.rds.read_iops{...同タグ}` / `aws.rds.write_iops{...同タグ}` | `avg`。回/秒 | 同上 |
| `alb-code` | ALB のステータスコード別リクエスト数 | §3.1 台帳 | metrics | `httpcode_target_2xx` / `httpcode_elb_3xx` / `elb_4xx` / `elb_5xx`。タグ `{service:{{P.api_service}}, env:production}` | `aggregator="sum"`, `.as_count()`。件 | 同上 |
| `alb-host` | ALB の健全ホスト数 | §3.1 台帳 | metrics | `healthy_host_count` / `un_healthy_host_count`。タグは `alb-code` と同じ | `avg`。台 | 同上 |
| `rails-latency` | Rails のレイテンシ分布 | §3.1 台帳 | metrics | `p50:trace.rack.request{service:{{P.api_service}}}` と `p95:` | `avg`（週平均）と `max`（週中最大）。秒なので ×1000 で ms | 同上 |
| `rails-hits` | Rails のリクエスト数（週計） | §3.1 台帳 | metrics | `sum:trace.rack.request.hits{service:{{P.api_service}}}.as_count()` | `sum`。件 | 同上 |
| `job-latency` | ジョブのレイテンシ | §3.1 台帳 | metrics | `p50:{{P.job_metric}}` | `avg`。秒なので ×1000 で ms | 同上 |
| `job-hits` | ジョブの処理件数（週計） | §3.1 台帳 | metrics | {{P.job_hits}} | `sum`。件 | 同上 |
| `prev-report` | 前週レポートの Decide / Act とその反映状況 | §1 / §3 | Notion | 出力先 DB を作成日時 DESC で1件。該当箇所だけ読む（`collect.md`） | — | 「前週レポート参照不可」と明記 |

{{P:query-catalog}}

## 発火時のみ取得

アプリ調査トリガが ON の週だけ引く。
使いどころと切り分けの狙いは `investigate.md`。

| ID | 目的 | 記載先 | 種別 | クエリ / 取得条件 | 集計・単位 | 欠損時 |
| --- | --- | --- | --- | --- | --- | --- |
| `win-latency` | 発火ウインドウ内のレイテンシ分布 | §2 の一次調査 | metrics | `p50:` / `p90:` / `p95:trace.rack.request{service:{{P.api_service}}}`。ジョブ側は `{{P.job_metric}}`。`from` / `to` に発火ウインドウを渡す | `avg` と `max` を別コールで。ms | その項目を `⚠️ 取得不可` とし、Orient では推測しない |
| `win-hits` | ウインドウ内のリクエスト数（負荷増との交絡の切り分け） | §2 の一次調査 | metrics | `rails-hits` と同じクエリにウインドウを渡す | `sum`。件 | 同上 |
| `win-resource` | 重い resource_name の上位 | §2 の調査表 | metrics | `rails-latency` / `job-latency` を `by {resource_name}` で。p50 降順の上位15 | `avg`。ms | 同上 |
| `slow-span` | 個々の遅いスパン（集約で消える外れ値） | §2 の一次調査 | spans | `search_datadog_spans` に `query="env:production @duration:>30000000000"`（ns）、`sort="-@duration"` | duration 降順の生スパン。ns | 同上 |
| `slow-trace` | 支配スパンの特定 | §2 の一次調査 | traces | `get_datadog_trace(trace_id)` の waterfall。`slow-span` で拾った trace_id を渡す | — | 同上 |
| `dash-diff` | ダッシュボード構成の前週差分（任意） | §3.3 | dashboard | `get_datadog_dashboard(dashboard_id="{{P.dashboard}}")`。必要な widget に絞る | — | 省略してよい（任意の手順） |

## 取得時の罠

数値を誤らせる罠は [docs/datadog-mcp-tips.md](../../../docs/datadog-mcp-tips.md) にまとまっている。
**メトリクスを取る前に読む。** 特に次の3つはカタログの値に直接効く。

- **vCPU 正規化**：生の `ecs.fargate.cpu.percent` は単一 vCPU 基準で、複数 vCPU 割当のタスクでは 100% を超える。`ecs-cpu` の式（`cpu.task.limit / 1e9` で割る）を使い、閾値と直接比較しない。
- **`.rollup(avg, 3600)` の省略**：rollup なしの素の `aggregator="max"` は1分粒度の瞬間生値ピーク（API CPU 197% など）を拾い、monitor の閾値と整合しない。持続的なピークを見る指標には必ず埋める。
- **scalar dedup**：`response_format="scalar"` で同一クエリ文字列を `aggregator` 違いに複数渡すと、結果が1つに統合されて avg と max を区別できなくなる。両方要る指標は別コールに分けるか、`timeseries` で取得して自分で算出する。

`aggregate_spans` の `group_by` 付きは 0 buckets を返すことがある。
最悪スパンの特定は `slow-span` の duration 降順検索を主軸にする。

## 台帳への記録

常時取得の値は、発火の有無にかかわらず毎週 §3.1 の台帳に記録する。
§2 は発火したものだけを書くので、静かな週の数値の唯一の住所が台帳になる。

台帳の「校正メモ」列は毎週埋める。
monitor の校正不良（鈍くて鳴らない、鳴りすぎて非事象）を可視化する唯一の場所なので、空のまま出さない。
記法は `templates/report.md` §3.1 のガイドにある。
