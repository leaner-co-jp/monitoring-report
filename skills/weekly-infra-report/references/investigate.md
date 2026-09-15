# 調査（手順4-b〜4-d）

**トリガ ON の週だけ読む。** トリガ OFF（monitor の発火なし）の週にこのファイルを読む必要はない。判定は `references/collect.md` 手順4-a。

<aside>
⚠️

アプリのトレース詳細調査は**インフラ側の異常シグナルが出た週だけ**実施する。恒常的な劣化はインフラ monitor + SLO + Sentry がカバーしており、シグナルの無い週に per-endpoint 探索を行っても、import 系（レスポンスがデータ量に比例）の誤検知とトークンを生むだけのため。

</aside>

## プロダクト固有の調査前提

{{P:domain-notes}}

---

## 手順4-c. トリガ ON の週のトレース調査

インシデントの**時間ウインドウに絞って**（手順2の発火 → 復旧 epoch。SLO 劣化なら該当バーンレートのウインドウ または 当日）`get_datadog_metric` でトレース調査する。ウインドウの `from` / `to` を全クエリに渡し、「どのエンドポイント／ジョブが・いつ遅かったか」を特定する。**結果はテンプレート §2.x に「インシデント単位で1節」として書く**（レイヤ別に分けない。同時刻に鳴った複数 monitor は1節に束ねて1つの原因仮説にまとめる）。

### レイテンシ分布の刻み

p50 / p90 / p95: `queries=["p50:trace.rack.request{service:{{P.api_service}}}", "p90:...", "p95:..."]`。`aggregator="avg"`（ウインドウ平均）と `aggregator="max"`（ウインドウ中の最大）で取得（×1000 で ms）。ジョブ側も `{{P.job_metric}}` で同様。p99 だけ伸びる = テール劣化 / 全体がシフト = 負荷増、と切り分ける。

⚠️ **scalar dedup の罠**: `response_format="scalar"` で**同一クエリ文字列**を `aggregator` 違いで複数渡すと、結果が1つに統合され avg と max を区別できなくなる。avg と max の両方が要る指標は **(a) 別々の `get_datadog_metric` コールに分ける**か、**(b) `timeseries` で取得して自前で avg / max を算出する**。

### 分母（交絡の切り分け用）

Rails リクエスト数 `sum:trace.rack.request.hits{service:{{P.api_service}}}.as_count()`（`aggregator="sum"`）、{{P.job_hits}}。「p95 +20%」が「トラフィック +40%」由来かを判別する。

### 重い resource_name Top 15

Rails / {{P.job_backend}} それぞれ `by {resource_name}` で `aggregator="avg"`、p50 降順の上位15。週全体で重い endpoint を俯瞰するなら APM サービスページ（テンプレート冒頭の「🔗 調査リンク」）も併用する。

**§2.x の調査表に載せる基準**: 劣化 = ウインドウ内 p50 が平常比 **+50% 以上** または **+500ms 以上**。改善 = p50 が先週比 **−30% 以上** または **−500ms 以上**。この基準に届かないものは表に載せない（表を埋めるために基準を緩めない）。

### 個々の遅いトレース／SQL の検知（p50 / avg 集約では見えない外れ値）

p50 / avg は単発の長時間トレース（60s 級の重い SQL など）を平滑化して見落とす。RDS Writer CPU / ECS の critical・warning ウインドウでは、`search_datadog_spans` を `query="env:production @duration:>30000000000"`（ns 単位。閾値は適宜）・`sort="-@duration"` で **duration 降順**に引き、個々の遅いスパンを直接列挙する（APM Trace Explorer の duration 降順スパンビュー相当）。

- root（`rack.request`）だけでなく **DB クライアント層まで見る**。`rails.db.runtime` が大きければ DB 起因と判定。支配スパンの特定は `get_datadog_trace(trace_id)` の waterfall で行う。メトリクスで見る場合も p50 ではなく `max` / p99 を使う。
- ⚠️ `aggregate_spans` の `MAX(duration) by {service, resource_name}` は 0 buckets を返すことがある（facet 化の癖。events の group_by と同様）。最悪スパンの特定は `search_datadog_spans` の duration 降順 search を主軸にする。
- RDS Writer CPU / コネクション critical の一次調査（手順4-d）では、この duration 降順検索で「その時刻に Writer 宛（`peer.hostname` が `{{P.db_cluster}}.cluster-…`）に出ていた重い SQL」を特定し、悪化の主体を『実際に DB を叩いた endpoint / SQL』に置く。書き込み系ジョブ等は同ウインドウに居るだけで主体と断定せず（p50 集約だけの相関による当て推量を避ける）、duration 降順の実スパンで裏付ける。

---

## 手順4-d. critical 発火時の周辺リソース相関調査（プレイブック）

critical シグナルが出たときは、発火した monitor を単独で見ず、**発火種別に応じて隣接リソースまで同一ウインドウで広げて調べ、悪化の「主体」と「上流原因」を切り分ける**。すべて手順2のインシデントウインドウ（発火 → 復旧 epoch）を全クエリの `from` / `to` に渡し、各 finding にはそのウインドウの deep link を添える（リンク規約は `references/output.md`）。

| 発火した monitor | 一次調査（悪化の主体） | 相関して見る周辺リソース（上流／下流） | 切り分けの狙い |
| --- | --- | --- | --- |
| ECS API CPU / メモリ | `{{P.api_service}}` の APM トレース（ウインドウ内の p50 / p95、Top resource_name、リクエスト数） | RDS Writer（CPU・コネクション・遅いクエリ）/ ALB リクエスト数 / 同時刻のデプロイ | リクエスト増による負荷か、特定 endpoint の劣化か、DB 待ちでの滞留か |
| ECS Worker 系 CPU / メモリ | `{{P.worker_service}}` の APM トレース（`{{P.job_metric_short}}` ウインドウ内、重い resource_name） | {{P.job_backend}} 件数 / RDS / {{P.worker_correlates}} | 単発の重いジョブ（{{P.heavy_jobs}}）か、滞留の積み上がりか |
| RDS Writer CPU / コネクション | RDS の DB スパン（APM の `sql` resource、ウインドウ内の遅いクエリ Top） | 発生源サービスの DB スパン（`{{P.api_service}}` / `{{P.worker_service}}`）/ ECS CPU / 重いジョブ | コネクション枯渇か、特定クエリの劣化か、ジョブ起因の書き込み集中か |
| ALB 5xx (elb) / Healthy ホスト `< 1` | ECS タスク状態（`healthy_host_count` の落ち込み）、タスク再起動・デプロイのタイミング | ECS CPU / メモリ（OOM kill → unhealthy）/ 同時刻のデプロイイベント | インフラ層の失敗（タイムアウト・ヘルシーホスト無し）。アプリ 5xx は Sentry 管轄（テンプレート §2 冒頭の「調査時の前提」）なので追わない |
| {{P.job_backend}} p95 anomaly | `{{P.worker_service}}` の APM トレース（ウインドウ内の重いジョブ resource_name） | Worker 系 ECS CPU / メモリ / RDS | 単発の重いペイロードか、リソース枯渇起因か、anomaly の誤検知か |
| SLO バーンレート / エラーバジェット | 劣化した SLO で分岐: 可用性 → ALB 5xx・Healthy ホスト / レスポンス → `{{P.api_service}}` p95 と劣化 endpoint | バーンレート `> 1` の時間帯に絞ったトレース（ダッシュボードノート推奨） | どの SLI 成分が・いつ・どの endpoint で割れたか |

{{P:playbook-notes}}

<aside>
📌

因果は両方向あり得る（DB が遅い → API CPU が上がる、ジョブが重い → Worker メモリが膨らむ）。一次調査で「悪化の主体」を、相関チェックで「上流原因」を当て、Orient に**主体と原因を分けて**書く。複数の monitor が同時刻に鳴っていれば、それらは同一インシデントの別側面である可能性が高いので、束ねて1つの原因仮説にまとめる（§2 に別々の節を立てない）。

</aside>
