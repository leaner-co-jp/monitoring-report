# PU（リーナー購買）固有値

> **これは完成形のテンプレートではない。** 共通手順は agent 非依存の `skills/weekly-infra-report/`、共通レポートテンプレートは [report.md](report.md) にある。本ファイルはそこに差し込む**PU 固有の値とブロック**だけを持つ。

## 変数

共通側の `{{P.xxx}}` に差し込む。

| 変数 | 値 |
| --- | --- |
| `{{P.name}}` | リーナー購買 |
| `{{P.code}}` | pu |
| `{{P.team}}` | pu |
| `{{P.window_ja}}` | 金曜〜木曜 |
| `{{P.window_start_ja}}` | 金 |
| `{{P.window_end_ja}}` | 木 |
| `{{P.report_title}}` | リーナー購買インフラモニタリング 週次レポート |
| `{{P.dashboard}}` | gbr-uqr-m74 |
| `{{P.api_service}}` | purchasing-api |
| `{{P.worker_service}}` | purchasing-worker |
| `{{P.job_backend}}` | ActiveJob |
| `{{P.job_metric}}` | trace.active_job.perform{service:purchasing-worker,env:production} |
| `{{P.job_metric_short}}` | trace.active_job.perform |
| `{{P.job_hits}}` | ActiveJob 件数 `sum:trace.active_job.perform.hits{service:purchasing-worker,env:production}.as_count()` も同様 |
| `{{P.db_cluster}}` | catalog-db-prd |
| `{{P.heavy_jobs}}` | import 系・mailer 系 |
| `{{P.worker_correlates}}` | 同時刻の重いジョブ |
| `{{P.db_name}}` | 📊 PU Dev インフラモニタリング週次レポート |
| `{{P.output_db}}` | https://www.notion.so/leanercojp/353daeae0b01805385baeab262ed18ea |
| `{{P.datasource}}` | collection://353daeae-0b01-8019-b309-000bbd54791b |
| `{{P.title_prop}}` | 名前 |

---

## {{P:targets}}

| 項目 | 値 |
| --- | --- |
| SLO: API可用性（30d, target 99.9%） | `3997c6b91fde5ac3ac382a13e209a32f` |
| SLO: APIレスポンス（30d, target 95%） | `34a6197fcb8b569498c42fd5281dffeb` |
| APM Rails service | `purchasing-api` |
| Worker APM メトリクス | `trace.active_job.perform{service:purchasing-worker,env:production}`（Solid Queue は ActiveJob 経由。✅ データ取得可） |
| ECS API service | `purchasing-production-api-service-t7be14m1403n`（タスクメモリ 8 GiB） |
| ECS Worker service | `purchasing-production-worker-service-ydlu96mimsfg`（タスクメモリ 2 GiB） |
| ALB service タグ | `service:purchasing-api, env:production` |
| RDS クラスタ | `catalog-db-prd`（Aurora, Writer/Reader） |
| AWS account（SES/WAF タグ） | `083068756812` |
| ダッシュボード | `gbr-uqr-m74` |

---

## {{P:monitors}}

取得される PU monitor は **13本**（2026-06-24 デプロイ実測。名称はいずれも `[リーナー購買] …` / SLO は `[リーナー購買 …]`）:

- **SLO（4本）**: `[リーナー購買 API可用性] エラーバジェット`（#172046752, error_budget `> 100` = 枯渇）/ `[リーナー購買 API可用性] バーンレート`（#172046754, burn_rate `> 14.4`）/ `[リーナー購買 APIレスポンスタイム] エラーバジェット`（#172046749）/ `[リーナー購買 APIレスポンスタイム] バーンレート`（#172046750）
- **ALB（2本）**: `ALB 5xx エラー率`（#299299596, `> 1.5%`）/ `ALB の Healthy ホストが存在しません`（#299299603, `< 1` = 全断）
- **ECS（4本）**: `ECS API CPU`（#299299608, `> 95%`）/ `ECS API メモリ`（#299299591, `> 95%`, 8 GiB）/ `ECS Worker CPU`（#299299609, `> 95%`）/ `ECS Worker メモリ`（#299299606, `> 95%`, 2 GiB）
- **RDS（2本）**: `RDS Writer CPU`（#299299599, `> 90%`）/ `RDS Writer コネクション`（#299299605, `> 9500`）
- **Job（1本）**: `ActiveJob レイテンシ(p95) 異常`（#299299595, anomaly agile 2σ, `trace.active_job.perform{service:purchasing-worker}`）

<aside>
📌

**LP と異なり、PU には Worker-Long / Worker-Mailer・default queue 滞留・WAF / SES の monitor は存在しない**。Worker サービスは1つに統合されている。

</aside>

---

## {{P:thresholds}}

リーナー購買の評価閾値（= monitor の実値）:

| 指標 | 🟡 warning | 🔴 critical |
| --- | --- | --- |
| ECS メモリ %（API / Worker 共通） | 80% | 95% |
| ECS CPU %（API / Worker 共通、vCPU 正規化） | 90% | 95% |
| RDS Writer コネクション数 | 9000 | 9500 |
| RDS Writer CPU % | 75% | 90% |
| ALB 5xx エラー率 | 0.5% | 1.5% |
| ALB Healthy ホスト数 | — | `< 1`（全断） |
| ActiveJob p95 レイテンシ | — | anomaly（agile, 2σ 乖離） |
| SLO エラーバジェット（API可用性 / APIレスポンス） | — | 枯渇（consumed `> 100%`） |
| SLO バーンレート（1h / 5m） | — | `> 14.4` |

**WAF / SES / RDS Reader には monitor が存在しないため判定対象外**（上表にも載せない）。数値は参考値として扱い、色を付けない。

**旧方式からの変更点（2026-08-26）**: PU は従来「評価色 = monitor 状態（OK/Warn/Alert）にそのまま一致」させていた。LP v2 のルールに合わせ、**色と severity（発火の重さ）を切り離す**方式に変更した。critical が出ても自動復旧・波及なしなら 🟢（記録のみ）に落ちる（`references/evaluate.md` の判定順序を参照）。

---

## {{P:metric-queries}}

- **ECS（2サービス）**: API `purchasing-production-api-service-t7be14m1403n`（8 GiB）/ Worker `purchasing-production-worker-service-ydlu96mimsfg`（2 GiB）
- **RDS Writer / Reader**: タグ `{env:production, dbclusteridentifier:catalog-db-prd, role:<role>}`。
- **ALB**: タグ `{service:purchasing-api, env:production}`。
- **ActiveJob**: 件数・p50 は `trace.active_job.perform{service:purchasing-worker,env:production}`。`solidqueue::recurringjob` と `activestorage::purgejob` は除外する。

---

## {{P:known-issues}}

<aside>
⚠️

**リーナー購買固有の既知事項**:

1. Worker は **Solid Queue（ActiveJob 経由）**。メトリクスは span 名込みの `trace.active_job.perform{service:purchasing-worker,env:production}` を使う。`trace.active_job{...}`（span名なし）や `trace.solid_queue.*` は使わない。`solidqueue::recurringjob` と `activestorage::purgejob` はフレームワーク / 定期メンテナンス系として劣化調査・Decide 候補から除外する。
2. **ダッシュボード `gbr-uqr-m74` には WAF / SES セクションがあるが、monitor は存在しない**。monitor 駆動の本レポートでは WAF / SES を扱わない（シグナルソースが無いため）。必要になれば monitor を追加してから取り込む。
3. RDS Reader が現状ほぼ未活用なら「読み取りクエリ分散検討」を恒久課題として §1 に残す（初出時のみ内容記載、以降は件数のみ）。Reader には専用 monitor が無いため色は付けず、手順5 の参考値として記載する。
4. **forecast（キャパシティ予測）は週次レポートでは扱わない**（精度の問題から月次など別頻度に分離する）。
</aside>

---

## {{P:domain-notes}}

**調査除外ジョブの扱い**

`solidqueue::recurringjob` と `activestorage::purgejob` は Solid Queue のフレームワーク処理・定期メンテナンス処理であり、実行時間が長く見えても購買業務そのものの負荷を示す指標ではない。

- これらが `trace.active_job.perform` の p95 / duration や重い `resource_name` の上位に出ても、**ECS Worker の CPU / メモリや RDS Writer CPU / コネクションの直接原因とはみなさない**。直接原因の候補は「リーナー購買側で実際に業務処理を行うジョブ（import 系・mailer 系など）」に置く。
- ただし**キュー滞留・Worker スループットの観点では占有時間として影響する**ため、滞留のシグナルが出た週の一次調査対象からは除外しない。
- RDS Writer CPU / ECS Worker の critical・warning の因果を書くときは、この切り分けを **§2 冒頭の「調査時の前提」・§1 の総合ステータス・§2.x の Orient に一貫して明記**する。

---

## {{P:playbook-notes}}

- Worker サービスは1つ（`purchasing-production-worker-service-ydlu96mimsfg`）。一次調査の重い `resource_name` からは**除外ジョブ**（`solidqueue::recurringjob` / `activestorage::purgejob`）を外して見る。

---

## {{P:investigation-premises}}

- **`solidqueue::recurringjob` / `activestorage::purgejob`**（フレームワーク / 定期メンテナンス処理）は、`trace.active_job.perform` の p50 / p95 が長くても ECS Worker / RDS Writer の負荷の直接原因とはみなさない。直接原因の候補は「実際に業務処理を行うジョブ（import 系・mailer 系など）」に置く。ただしキュー滞留・Worker スループットの観点では占有時間として影響するため、調査対象からは除外しない。

---

## {{P:signal-guide-note}}

ECS メモリは API / Worker の2サービスのうち高い方を1行にまとめ、どのサービスかを併記する。

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
| アプリ | ActiveJob p50（週平均） | `{{ms}}` | `{{ms}}` | `{{±%}}` | `{{発火なし|critical N回 / N分}}` |  |
| アプリ | ActiveJob 処理件数 | `{{N}}` | `{{N}}` | `{{±%}}` | — |  |
| ALB | 2xx（週計） | `{{N}}` | `{{N}}` | `{{±%}}` | — |  |
| ALB | 4xx elb（週計 / 率） | `{{N}}`（`{{%}}`） | `{{N}}`（`{{%}}`） | `{{±%}}` | — |  |
| ALB | 5xx elb（週計 / 率） | `{{N}}`（`{{%}}`） | `{{N}}`（`{{%}}`） | `{{±%}}` | `{{発火なし|critical N回 / N分}}` |  |
| ALB | Healthy / Unhealthy host (avg) | `{{N}}` / `{{N}}` | `{{N}}` / `{{N}}` |  | `{{発火なし|critical N回 / N分}}` |  |
| ECS | API CPU max / avg（8 GiB） | `{{%}}` / `{{%}}` | `{{%}}` / `{{%}}` | `{{±ppt}}` | `{{発火なし|critical N回 / N分}}` |  |
| ECS | API メモリ max% / avg% | `{{%}}` / `{{%}}` | `{{%}}` / `{{%}}` | `{{±ppt}}` | `{{発火なし|critical N回 / N分}}` |  |
| ECS | Worker CPU max / メモリ max%（2 GiB） | `{{%}}` / `{{%}}` | `{{%}}` / `{{%}}` | `{{±ppt}}` | `{{発火なし|critical N回 / N分}}` |  |
| RDS | Writer CPU max / avg | `{{%}}` / `{{%}}` | `{{%}}` / `{{%}}` | `{{±ppt}}` | `{{発火なし|critical N回 / N分}}` |  |
| RDS | Writer Conn max / avg | `{{N}}` / `{{N}}` | `{{N}}` / `{{N}}` | `{{±}}` | `{{発火なし|critical N回 / N分}}` |  |
| RDS | Writer Free Memory (avg) | `{{GiB}}` | `{{GiB}}` | `{{±%}}` | — |  |
| RDS | Reader CPU max / Conn | `{{%}}` / `{{N}}` | `{{%}}` / `{{N}}` |  | — | `{{ Conn = 0 なら「未活用」と明記 }}` |
| RDS | IOPS read / write (avg) | `{{N}}`/s / `{{N}}`/s | `{{N}}`/s / `{{N}}`/s | `{{±%}}` | — | 参考値 |

<aside>
⚠️

- RDS IOPS は rate メトリクスで `.as_count()` が自動適用されるため、週合計の絶対値は参考値。先週比のトレンドのみ評価する。
- ALB は `httpcode_elb_*`（ALB レイヤ自身）のみを記録している。`httpcode_target_5xx`（アプリが返した 5xx）は Sentry 管轄のため本表には含まれない。
</aside>
