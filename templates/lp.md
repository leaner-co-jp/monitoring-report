# LP（リーナー見積）固有値

> **これは完成形のテンプレートではない。** 共通手順は agent 非依存の `skills/weekly-infra-report/`、共通レポートテンプレートは [report.md](report.md) にある。本ファイルはそこに差し込む**LP 固有の値とブロック**だけを持つ。

## 変数

共通側の `{{P.xxx}}` に差し込む。

| 変数 | 値 |
| --- | --- |
| `{{P.name}}` | リーナー見積 |
| `{{P.code}}` | lp |
| `{{P.team}}` | lp |
| `{{P.window_ja}}` | 水曜〜火曜 |
| `{{P.window_start_ja}}` | 水 |
| `{{P.window_end_ja}}` | 火 |
| `{{P.report_title}}` | リーナー見積インフラモニタリング 週次レポート |
| `{{P.dashboard}}` | nnu-w8q-2yz |
| `{{P.api_service}}` | procurement-api |
| `{{P.worker_service}}` | procurement-worker |
| `{{P.job_backend}}` | Delayed::Job |
| `{{P.job_metric}}` | trace.delayed_job{service:procurement-worker} |
| `{{P.job_metric_short}}` | trace.delayed_job |
| `{{P.job_hits}}` | Delayed::Job 件数も同様 |
| `{{P.db_cluster}}` | prd-ecs-db-cluster |
| `{{P.heavy_jobs}}` | compress 系・supplier_email 系 |
| `{{P.worker_correlates}}` | SES 送信量（Mailer） |
| `{{P.db_name}}` | 📊 LP Dev インフラモニタリング週次レポート |
| `{{P.output_db}}` | https://www.notion.so/leanercojp/353daeae0b0180528fa0c6c212b74441 |
| `{{P.datasource}}` | collection://353daeae-0b01-8043-bd60-000b0cef4826 |
| `{{P.title_prop}}` | ドキュメント名 |

---

## {{P:targets}}

| 項目 | 値 |
| --- | --- |
| SLO: API可用性（30d, target 99.9%） | `b56ae57a387f51bcb0ac9732cc05718f` |
| SLO: APIレスポンス（30d, target 95%） | `1702a34221e95c85aa455dc43bd216a7` |
| APM Rails service | `procurement-api` |
| Worker APM メトリクス | `trace.delayed_job`（✅ データ取得可） |
| ECS API service | `procurement-production-api-service-w0bji1nrnqop`（タスクメモリ 8 GiB） |
| ECS Worker service | `procurement-production-worker-service-gwicbkyhasqz`（タスクメモリ 2 GiB） |
| ECS Worker-Long service | `procurement-production-worker-long-service-ucqjdrqmvu4a`（タスクメモリ 1 GiB） |
| ECS Worker-Mailer service | `procurement-production-worker-mailer-service-bsk312etaj9j`（タスクメモリ 1 GiB） |
| ECS MultimodalAPI service | `procurement-production-multimodal-api-service-zcucozmazvpg`（**0.5 vCPU** / タスクメモリ 2 GiB）※ monitor なし |
| ALB service タグ | `service:procurement-api, env:production` |
| RDS クラスタ | `prd-ecs-db-cluster`（Aurora MySQL, Writer/Reader） |
| RDS クラスタ（pgvector） | `prd-multimodal-api-pgvector`（Aurora PostgreSQL, **Writer のみ**。インスタンスメモリ 2 GiB）※ monitor なし |
| デプロイ相関のサービス名（MultimodalAPI 系） | `multimodal-api`（ダッシュボードの change_tracking オーバーレイが使用） |
| ダッシュボード | `nnu-w8q-2yz` |

---

## {{P:monitors}}

取得される LP monitor は **17本**（2026-08-21 実測。名称はいずれも `[リーナー見積] …`）:

- **SLO（4本）**: `API可用性 エラーバジェット`（#170756934, error_budget `> 100` = 枯渇）/ `API可用性 バーンレート`（#170532501, burn_rate `> 14.4`）/ `APIレスポンスタイム エラーバジェット`（#170756933）/ `APIレスポンスタイム バーンレート`（#170532500）
- **ALB（2本）**: `ALB 5xx エラー率`（#297262489, `> 1.5%`）/ `ALB Healthy ホスト`（`< 1` = 全断）
- **ECS（8本）**: `API` / `Worker` / `Worker-Long` / `Worker-Mailer` の `CPU`（`> 95%`）と `メモリ`（`> 95%`）各4本
- **RDS（2本）**: `RDS Writer コネクション`（`> 9500`）/ `RDS Writer CPU`（#297262491, `> 90%`）
- **Job（1本）**: `Delayed::Job レイテンシ(p95) 異常`（anomaly）

monitor ID の全件表は [docs/monitors.md](../docs/monitors.md) にある。

<aside>
⚠️

**ダッシュボードにあって monitor が無いリソースがある**（2026-09-15 時点）: **MultimodalAPI ECS**（`procurement-production-multimodal-api-service-zcucozmazvpg`）と **Aurora PostgreSQL / pgvector**（`prd-multimodal-api-pgvector`）。上の17本にはこれらの monitor が含まれない。

この2つは**判定対象外の参考値**として扱う — 色を付けず、独自閾値で評価しない。数値は手順5 で取得して §3.1 の台帳にのみ記録し、先週比 ±20% 以上動いた週は §1 の「monitor 以外で動いた指標」に書く。閾値による判定が必要になったら、レポートで判定するのではなく monitor を作る（`leaner-terraform` の `environments/datadog/`）。

</aside>

---

## {{P:thresholds}}

リーナー見積の評価閾値（= monitor の実値）:

| 指標 | 🟡 warning | 🔴 critical |
| --- | --- | --- |
| ECS メモリ %（API / Worker / Worker-Long / Worker-Mailer 共通） | 80% | 95% |
| ECS CPU %（4サービス共通） | 90% | 95% |
| RDS Writer コネクション数 | 9000 | 9500（現上限 10000） |
| RDS Writer CPU % | 75% | 90% |
| ALB 5xx エラー率 | 0.5% | 1.5% |
| ALB Healthy ホスト数 | — | `< 1`（全断） |
| Delayed::Job p95 レイテンシ | — | anomaly（agile, 2σ 乖離） |
| SLO エラーバジェット（API可用性 / APIレスポンス） | — | 枯渇（consumed `> 100%`） |
| SLO バーンレート（1h / 5m） | — | `> 14.4` |

**MultimodalAPI ECS / pgvector RDS は monitor が存在しないため判定対象外**（上表にも載せない）。数値は §3.1 の台帳に参考値として記録し、色を付けない。

---

## {{P:query-catalog}}

LP 固有の対象と、共通行に対する差分。

| ID | 目的 | 記載先 | 種別 | クエリ / 取得条件 | 集計・単位 | 欠損時 |
| --- | --- | --- | --- | --- | --- | --- |
| `ecs-mem` / `ecs-cpu` の対象 | ECS 4サービス | §3.1 台帳 | metrics | API `procurement-production-api-service-w0bji1nrnqop`（8 GiB）/ Worker `procurement-production-worker-service-gwicbkyhasqz`（2 GiB）/ Worker-Long `procurement-production-worker-long-service-ucqjdrqmvu4a`（1 GiB）/ Worker-Mailer `procurement-production-worker-mailer-service-bsk312etaj9j`（1 GiB） | 共通行と同じ | 行ごとに取得不可 |
| `ecs-multimodal` | MultimodalAPI の CPU とメモリ（monitor なしの参考値） | §3.1 台帳 | metrics | `procurement-production-multimodal-api-service-zcucozmazvpg`（0.5 vCPU / 2 GiB）。式は `ecs-cpu` / `ecs-mem` と同じ | 共通行と同じ。⚠️ CPU 正規化の分母は `cpu.task.limit / 1000000000` = `0.5`（raw の2倍が正規化値） | 行ごとに取得不可 |
| `rds-pg-*` | pgvector Writer の CPU、コネクション、空きメモリ、IOPS、キャッシュヒット率 | §3.1 台帳 | metrics | タグ `{env:production, dbclusteridentifier:prd-multimodal-api-pgvector, role:writer}`。`aws.rds.buffer_cache_hit_ratio` を追加で引く。max を取る指標は `.rollup(avg, 3600)` を埋める | 共通行と同じ | 行ごとに取得不可 |

- **`rds-*` の対象クラスタ**：`prd-ecs-db-cluster`（Aurora MySQL, Writer/Reader）。
- **pgvector に Reader は存在しない**ので `role:reader` は引かない（空になる）。
- ⚠️ **ダッシュボードの「MultimodalAPI CPU使用率」ウィジェットは式が誤っている。** 0.5 vCPU のタスクに `cpu.percent / 2` を使っており、真値の 1/4 を表示する。ウィジェットの値を台帳に転記せず、必ず `ecs-cpu` の式で取得し直す。
- **MultimodalAPI と pgvector には monitor が無い。** 判定対象外の参考値として台帳にのみ記録し、色を付けない。

---

## {{P:known-issues}}

<aside>
⚠️

**リーナー見積固有の既知事項**:

1. 本ダッシュボードには **WAF / SES セクションがない**。レポートでも記載しない。
2. **Delayed::Job のメトリクス名は `trace.delayed_job`**（`trace.delayed_job.*` というサブスペース付きは存在しない。「単一スパン」タイプ）。
3. Worker-Long / Worker-Mailer はタスクメモリ 1 GiB と小さめ。**メモリ枯渇のリスクが相対的に高く、% ベースで見ると実際より高めに見える**点に注意。
4. **forecast（キャパシティ予測）は週次レポートでは扱わない**（精度の問題から月次など別頻度に分離する）。
5. **MultimodalAPI ECS と Aurora PostgreSQL（pgvector）には monitor が存在しない**（2026-09-15 時点）。ダッシュボードにセクションはあるが、シグナルソースが無いため**判定対象外の参考値**として台帳にのみ記録する。
6. **ダッシュボードの MultimodalAPI CPU ウィジェットは正規化式が誤っている。** 0.5 vCPU のタスクに対し `cpu.percent / 2` を使っており、正しい `/ 0.5` の 1/4 の値を表示する。**ウィジェットの値をレポートに転記しない**（手順5 の式で取得し直す）。
7. **pgvector の「メモリ平均使用率」ウィジェットは分母 2 GiB をハードコードしている**（`(2147483648 - freeable_memory) / 2147483648`）。インスタンスクラスを変えると黙って誤った値になるため、台帳には `freeable_memory` の実値（GiB）を記録する。
8. **ダッシュボードのフル取得は約 86k 文字**（MultimodalAPI / pgvector セクション追加のため増えた）。手順6 の構成差分確認はフル取得せず、必要な widget に絞る。
</aside>

---

## {{P:domain-notes}}

**外部ワークロードで実行される図面系ジョブの扱い**

`DetectDrawingReferenceJob` と `GenerateDrawingFileThumbnailsJob` は実行時間が長く見えやすいが、重い処理の実体はリーナー見積のインフラ外にある外部ワークロードで実行している。

- これらが `trace.delayed_job` の p95 / duration や重い `resource_name` の上位に出ても、**ECS Worker の CPU / メモリや RDS Writer CPU / コネクションの直接原因とはみなさない**。直接原因の候補は「リーナー見積側で実際に DB 書き込み・処理を行うジョブ（compress 系など）」に置く。
- ただし**キュー滞留・Worker スループットの観点では占有時間として影響する**ため、滞留のシグナルが出た週の一次調査対象からは除外しない。
- RDS Writer CPU / ECS Worker の critical・warning の因果を書くときは、この切り分け（外部ワークロード待ちの時間 vs リーナー見積側インフラ負荷）を **§2 冒頭の「調査時の前提」・§1 の総合ステータス・§2.x の Orient に一貫して明記**する。

---

## {{P:playbook-notes}}

- Worker 系は **Worker / Worker-Long / Worker-Mailer の3サービス**。どれが鳴ったかで一次調査の対象ジョブが変わる（Mailer なら supplier_email 系と SES 送信量）。Worker-Long / Worker-Mailer は 1 GiB と小さいためメモリ枯渇が早い。

---

## {{P:investigation-premises}}

- **図面系ジョブ**（`DetectDrawingReferenceJob` / `GenerateDrawingFileThumbnailsJob`）は重い処理の実体がリーナー見積のインフラ外の外部ワークロードにある。`trace.delayed_job` の p50 / p95 が長くても ECS Worker / RDS Writer の負荷の直接原因とはみなさない。直接原因の候補は「実際に DB 書き込み・処理を行うジョブ（compress 系など）」に置く。ただしキュー滞留・Worker スループットの観点では占有時間として影響するため、調査対象からは除外しない。

---

## {{P:signal-guide-note}}

ECS メモリは4サービス中の最高値を1行にまとめ、どのサービスかを併記する。

---

## {{P:signal-rows}}

| ECS メモリ 最高値 | `{{%}}`（`{{サービス名}}`） | `{{%}}`（`{{サービス名}}`） | `{{±ppt}}` | `{{ 閾値 80 / 95 に対する位置付け }}` |

---

## {{P:ledger}}

| レイヤ | 指標 | 今週 | 先週 | 変化 | monitor発火 | 校正メモ |
| --- | --- | --- | --- | --- | --- | --- |
| SLO | API可用性 SLI (30d) | `{{%}}` | `{{%}}` | `{{±ppt}}` | `{{発火なし|critical N回 / N分}}` |  |
| SLO | API可用性 EBR 残 | `{{%}}` | `{{%}}` | `{{±ppt}}` | `{{発火なし|critical N回 / N分}}` |  |
| SLO | API可用性 Bad events (raw) | `{{N}}` req | `{{N}}` req | `{{±%}}` | — |  |
| SLO | APIレスポンス SLI (30d) | `{{%}}` | `{{%}}` | `{{±ppt}}` | `{{発火なし|critical N回 / N分}}` |  |
| SLO | APIレスポンス EBR 残 | `{{%}}` | `{{%}}` | `{{±ppt}}` | `{{発火なし|critical N回 / N分}}` |  |
| SLO | APIレスポンス Bad events (raw) | `{{N}}` req | `{{N}}` req | `{{±%}}` | — |  |
| アプリ | Rails リクエスト数（週計） | `{{N}}` | `{{N}}` | `{{±%}}` | — |  |
| アプリ | Rails p50（週平均） | `{{ms}}` | `{{ms}}` | `{{±%}}` | — |  |
| アプリ | Rails p95（週平均） | `{{ms}}` | `{{ms}}` | `{{±%}}` | — |  |
| アプリ | Rails p95（週中最大） | `{{ms}}` | `{{ms}}` | `{{±%}}` | — |  |
| アプリ | Delayed::Job p50（週平均） | `{{ms}}` | `{{ms}}` | `{{±%}}` | `{{発火なし|critical N回 / N分}}` |  |
| アプリ | Delayed::Job 処理件数 | `{{N}}` | `{{N}}` | `{{±%}}` | — |  |
| ALB | 2xx（週計） | `{{N}}` | `{{N}}` | `{{±%}}` | — |  |
| ALB | 4xx elb（週計 / 率） | `{{N}}`（`{{%}}`） | `{{N}}`（`{{%}}`） | `{{±%}}` | — |  |
| ALB | 5xx elb（週計 / 率） | `{{N}}`（`{{%}}`） | `{{N}}`（`{{%}}`） | `{{±%}}` | `{{発火なし|critical N回 / N分}}` |  |
| ALB | Healthy / Unhealthy host (avg) | `{{N}}` / `{{N}}` | `{{N}}` / `{{N}}` |  | `{{発火なし|critical N回 / N分}}` |  |
| ECS | API CPU max / avg（8 GiB） | `{{%}}` / `{{%}}` | `{{%}}` / `{{%}}` | `{{±ppt}}` | `{{発火なし|critical N回 / N分}}` |  |
| ECS | API メモリ max% / avg% | `{{%}}` / `{{%}}` | `{{%}}` / `{{%}}` | `{{±ppt}}` | `{{発火なし|critical N回 / N分}}` |  |
| ECS | Worker CPU max / メモリ max%（2 GiB） | `{{%}}` / `{{%}}` | `{{%}}` / `{{%}}` | `{{±ppt}}` | `{{発火なし|critical N回 / N分}}` |  |
| ECS | Worker-Long CPU max / メモリ max%（1 GiB ⚠️） | `{{%}}` / `{{%}}` | `{{%}}` / `{{%}}` | `{{±ppt}}` | `{{発火なし|critical N回 / N分}}` |  |
| ECS | Worker-Mailer CPU max / メモリ max%（1 GiB ⚠️） | `{{%}}` / `{{%}}` | `{{%}}` / `{{%}}` | `{{±ppt}}` | `{{発火なし|critical N回 / N分}}` |  |
| ECS | MultimodalAPI CPU max / メモリ max%（0.5 vCPU / 2 GiB） | `{{%}}` / `{{%}}` | `{{%}}` / `{{%}}` | `{{±ppt}}` | — | —（monitor なし） |
| RDS | Writer CPU max / avg | `{{%}}` / `{{%}}` | `{{%}}` / `{{%}}` | `{{±ppt}}` | `{{発火なし|critical N回 / N分}}` |  |
| RDS | Writer Conn max / avg | `{{N}}` / `{{N}}` | `{{N}}` / `{{N}}` | `{{±}}` | `{{発火なし|critical N回 / N分}}` |  |
| RDS | Writer Free Memory (avg) | `{{GiB}}` | `{{GiB}}` | `{{±%}}` | — |  |
| RDS | Reader CPU max / Conn | `{{%}}` / `{{N}}` | `{{%}}` / `{{N}}` |  | — | `{{ Conn = 0 なら「未活用」と明記 }}` |
| RDS | IOPS read / write (avg) | `{{N}}`/s / `{{N}}`/s | `{{N}}`/s / `{{N}}`/s | `{{±%}}` | — | 参考値 |
| RDS(pg) | pgvector Writer CPU max / avg | `{{%}}` / `{{%}}` | `{{%}}` / `{{%}}` | `{{±ppt}}` | — | —（monitor なし） |
| RDS(pg) | pgvector Writer Conn max / avg | `{{N}}` / `{{N}}` | `{{N}}` / `{{N}}` | `{{±}}` | — | —（monitor なし） |
| RDS(pg) | pgvector Writer Free Memory (avg) | `{{GiB}}` | `{{GiB}}` | `{{±%}}` | — | —（monitor なし） |
| RDS(pg) | pgvector Writer キャッシュヒット率 (avg) | `{{%}}` | `{{%}}` | `{{±ppt}}` | — | —（monitor なし） |
| RDS(pg) | pgvector IOPS read / write (avg) | `{{N}}`/s / `{{N}}`/s | `{{N}}`/s / `{{N}}`/s | `{{±%}}` | — | 参考値 / —（monitor なし） |

<aside>
⚠️

- RDS IOPS は rate メトリクスで `.as_count()` が自動適用されるため、週合計の絶対値は参考値。先週比のトレンドのみ評価する。
- ALB は `httpcode_elb_*`（ALB レイヤ自身）のみを記録している。`httpcode_target_5xx`（アプリが返した 5xx）は Sentry 管轄のため本表には含まれない。
- **MultimodalAPI ECS と RDS(pg)（`prd-multimodal-api-pgvector`）は monitor が無いため判定対象外の参考値**。色を付けず、先週比のトレンドだけを評価する。このクラスタに Reader は存在しない。
- MultimodalAPI の CPU % は **`cpu.percent / 0.5`**（= raw ×2）の正規化値。ダッシュボードの同名ウィジェットは式が誤っており（`/ 2`）真値の 1/4 を表示するので、その値を転記しない。
</aside>
