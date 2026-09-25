# FJ（リーナーコネクト）固有値

> **これは完成形のテンプレートではない。** 共通手順は agent 非依存の `skills/weekly-infra-report/`、共通レポートテンプレートは [report.md](report.md) にある。本ファイルはそこに差し込む**FJ 固有の値とブロック**だけを持つ。

## 変数

共通側の `{{P.xxx}}` に差し込む。

| 変数 | 値 |
| --- | --- |
| `{{P.name}}` | リーナーコネクト |
| `{{P.code}}` | fj |
| `{{P.team}}` | connect |
| `{{P.window_ja}}` | 金曜〜木曜 |
| `{{P.window_start_ja}}` | 金 |
| `{{P.window_end_ja}}` | 木 |
| `{{P.report_title}}` | リーナーコネクトインフラモニタリング 週次レポート |
| `{{P.dashboard}}` | bqh-uzk-ipf |
| `{{P.api_service}}` | connect-api |
| `{{P.worker_service}}` | connect-worker |
| `{{P.job_backend}}` | ActiveJob |
| `{{P.job_metric}}` | trace.active_job.perform{service:connect-worker,env:production} |
| `{{P.job_metric_short}}` | trace.active_job.perform |
| `{{P.job_hits}}` | ActiveJob 件数 `sum:trace.active_job.perform.hits{service:connect-worker,env:production}.as_count()` も同様 |
| `{{P.db_cluster}}` | rds-connect-production |
| `{{P.heavy_jobs}}` | notification 系・mailer 系・import 系 |
| `{{P.worker_correlates}}` | 同時刻の重いジョブ |
| `{{P.db_name}}` | 📊 FJ Dev インフラモニタリング週次レポート |
| `{{P.output_db}}` | https://www.notion.so/leanercojp/353daeae0b01800c9c1fded19b699309 |
| `{{P.datasource}}` | collection://353daeae-0b01-8009-b6dc-000b67d1d842 |
| `{{P.title_prop}}` | ドキュメント名 |

⚠️ **team タグは `connect`。** `tag:report:weekly team:fj` では 0 件になる。

---

## {{P:targets}}

| 項目 | 値 |
| --- | --- |
| SLO: API可用性（30d, target 99.9%） | `8cfdd97cf17c5f768a7d34d09606fa0f` |
| SLO: APIレスポンス（30d, target 95%） | `78d6959885c65c9f8326ca34e605e32d` |
| APM Rails service | `connect-api` |
| Worker APM メトリクス | `trace.active_job.perform{service:connect-worker,env:production}`（Solid Queue は ActiveJob 経由。✅ データ取得可） |
| ECS API service | `connect-production-api-service-vqce1bfa4dby`（タスクメモリ **3 GiB** ⚠️ — PU/LP の 8 GiB より小さく、メモリ感度が高い） |
| ECS Worker service | `connect-production-worker-service-vvkujofkxht0`（タスクメモリ 2 GiB） |
| ALB service タグ | `service:connect-api, env:production` |
| RDS クラスタ | `rds-connect-production`（Aurora, Writer/Reader） |
| AWS account（SES タグ） | `856251792400` |
| ダッシュボード | `bqh-uzk-ipf` |

---

## {{P:monitors}}

<aside>
⚠️

**team タグは `connect`（`fj` ではない）。** `tag:report:weekly team:fj` では 0 件になる。`source:alert team:fj`（手順2）も同様。

</aside>

取得される FJ monitor は **13本**（2026-06-24 デプロイ実測。名称はいずれも `[リーナーコネクト] …` / SLO は `[リーナーコネクト …]`）:

- **SLO（4本）**: `[リーナーコネクト API可用性] エラーバジェット`（#172046751, error_budget `> 100` = 枯渇）/ `[リーナーコネクト API可用性] バーンレート`（#172046753, burn_rate `> 14.4`）/ `[リーナーコネクト APIレスポンスタイム] エラーバジェット`（#172046747）/ `[リーナーコネクト APIレスポンスタイム] バーンレート`（#172046748）
- **ALB（2本）**: `ALB 5xx エラー率`（#299299597, `> 1.5%`）/ `ALB の Healthy ホストが存在しません`（#299299594, `< 1` = 全断）
- **ECS（4本）**: `ECS API CPU`（#299299590, `> 95%`）/ `ECS API メモリ`（#299299607, `> 95%`, 3 GiB）/ `ECS Worker CPU`（#299299610, `> 95%`）/ `ECS Worker メモリ`（#299299592, `> 95%`, 2 GiB）
- **RDS（2本）**: `RDS Writer CPU`（#299299602, `> 90%`）/ `RDS Writer コネクション`（#299299598, `> 9500`）
- **Job（1本）**: `ActiveJob レイテンシ(p95) 異常`（#299299593, anomaly agile 2σ, `trace.active_job.perform{service:connect-worker}`）

<aside>
📌

**LP / PU と異なり、FJ には Worker-Long / Worker-Mailer・default queue 滞留・WAF の monitor は存在しない**。Worker サービスは1つに統合されている。SES 監視の monitor もない（ダッシュボードに SES セクションはあるが未接続）。

</aside>

---

## {{P:thresholds}}

リーナーコネクトの評価閾値（= monitor の実値）:

| 指標 | 🟡 warning | 🔴 critical |
| --- | --- | --- |
| ECS メモリ %（API / Worker 共通） | 80% | 95% |
| ECS CPU %（API / Worker 共通、vCPU 正規化） | 90% | 95% |
| RDS Writer コネクション数 | 9000 | 9500 |
| RDS Writer CPU % | 75% | 90% |
| ALB 5xx（elb）エラー率 | 0.5% | 1.5% |
| ALB Healthy ホスト数 | — | `< 1`（全断） |
| ActiveJob p95 レイテンシ | — | anomaly（agile, 2σ 乖離） |
| SLO エラーバジェット（API可用性 / APIレスポンス） | — | 枯渇（consumed `> 100%`） |
| SLO バーンレート（1h / 5m） | — | `> 14.4` |

- **ALB は target_*（品質判定の主軸）と elb_*（防御シグナル含む）を分けて評価する。** `elb_4xx` の増減は品質劣化を意味しない（既知事項4参照）。
- **SES / RDS Reader には monitor が存在しないため判定対象外**（上表にも載せない）。参考値として扱い、色を付けない。

**旧方式からの変更点（2026-08-27）**: FJ は従来「評価色 = monitor 状態（OK/Warn/Alert）にそのまま一致」させていた。LP v2 のルールに合わせ、**色と severity（発火の重さ）を切り離す**方式に変更した。critical が出ても自動復旧・波及なしなら 🟢（記録のみ）に落ちる（`references/evaluate.md` の判定順序を参照）。

---

## {{P:metric-queries}}

- **ECS（2サービス）**: API `connect-production-api-service-vqce1bfa4dby`（3 GiB ⚠️）/ Worker `connect-production-worker-service-vvkujofkxht0`（2 GiB）。⚠️ 素の `aggregator="max"` は瞬間生値ピーク（API CPU 84% / 101% 等）を拾うので `.rollup(avg, 3600)` を必ず埋める。
- **RDS Writer / Reader**: タグ `{env:production, dbclusteridentifier:rds-connect-production, role:<role>}`。
- **ALB**: タグ `{service:connect-api, env:production}`。**target_*（アプリ到達 = SLO 主軸）と elb_*（ALB レイヤ自身 = 防御シグナル含む）を分けて取得する**（既知事項4参照）。
- **ActiveJob**: 件数・p50 は `trace.active_job.perform{service:connect-worker,env:production}`。`solidqueue::recurringjob` と `activestorage::purgejob` は除外する。

---

## {{P:known-issues}}

<aside>
⚠️

**リーナーコネクト固有の既知事項**:

1. **API タスクメモリは 3 GiB**（PU / LP の 8 GiB より小さい）。同じ閾値（80 / 95）でも余裕が小さく、急なピークが致命傷になりやすい。API メモリは特に注視する。
2. Worker は **Solid Queue（ActiveJob 経由）**。メトリクスは span 名込みの `trace.active_job.perform{service:connect-worker,env:production}` を使う。`trace.active_job{...}`（span名なし）や `trace.solid_queue.*` は使わない。`solidqueue::recurringjob` と `activestorage::purgejob` はフレームワーク / 定期メンテナンス系として劣化調査・Decide 候補から除外する。
3. **本ダッシュボードに WAF は無い。SES セクションはあるが monitor は存在しない**。monitor 駆動の本レポートでは SES を扱わない（シグナルソースが無いため。必要になれば monitor を追加してから取り込む）。
4. **ALB は target / elb を分けて解釈する**: `httpcode_target_*xx`（アプリ到達）が SLO / 品質判定の主軸。`httpcode_elb_*xx`（ALB レイヤ自身）は、リスナールール「ドメイン以外のリクエストに 403 を返す」設定による直 IP スキャン等の**防御側シグナル**を含むため、品質閾値の対象にはせず量と推移のみ確認する。ALB 5xx monitor の numerator は `elb_5xx`（インフラ層のタイムアウト・502 等）で、アプリ 5xx は Sentry 管轄。
5. RDS Reader が現状ほぼ未活用なら「読み取りクエリ分散検討」を恒久課題として §1 に残す（初出時のみ内容記載、以降は件数のみ）。Reader には専用 monitor が無いため色は付けず、手順5 の参考値として記載する。
6. **forecast（キャパシティ予測）は週次レポートでは扱わない**（精度の問題から月次など別頻度に分離する）。
7. ダッシュボード全体は約 61k 文字と MCP 応答上限を超えるため、**フル取得はしない**（一時ファイル退避と生成停止の主要因）。
</aside>

---

## {{P:domain-notes}}

**調査除外ジョブの扱い**

`solidqueue::recurringjob` と `activestorage::purgejob` は Solid Queue のフレームワーク処理・定期メンテナンス処理であり、実行時間が長く見えてもリーナーコネクトの業務そのものの負荷を示す指標ではない。

- これらが `trace.active_job.perform` の p95 / duration や重い `resource_name` の上位に出ても、**ECS Worker の CPU / メモリや RDS Writer CPU / コネクションの直接原因とはみなさない**。直接原因の候補は「リーナーコネクト側で実際に業務処理を行うジョブ（notification 系・mailer 系・import 系など）」に置く。
- ただし**キュー滞留・Worker スループットの観点では占有時間として影響する**ため、滞留のシグナルが出た週の一次調査対象からは除外しない。
- RDS Writer CPU / ECS Worker の critical・warning の因果を書くときは、この切り分けを **§2 冒頭の「調査時の前提」・§1 の総合ステータス・§2.x の Orient に一貫して明記**する。

**ALB target / elb の分離と防御シグナルの扱い**

リーナーコネクトの ALB には、リスナールール「ドメイン以外のリクエストに 403 を返す」設定があり、直 IP スキャンなどへの応答が `elb_4xx` に計上される。これは品質劣化ではなく**防御が機能している証拠**。

- **品質判定の主軸は `target_*`**（アプリが実際に受け取ったリクエストへの応答）。SLO・ユーザー影響の評価はここを見る。
- **`elb_*` は ALB レイヤ自身の応答**で、防御シグナル（`elb_4xx`）とインフラ層の失敗（`elb_5xx`: タイムアウト・ヘルシーホスト無し・502 等）を含む。ALB 5xx monitor の numerator も `elb_5xx`。
- `elb_4xx` の増減は**量と推移のみ確認**し、単独では対応要否の判定に使わない（急増が正規リクエストへの影響を伴うか＝`target_4xx`/`target_5xx`/Healthy ホスト数と併読して判断する）。
- この区別は **§2 冒頭の「調査時の前提」と §3.1 台帳の ALB 注記**に一貫して明記する。

---

## {{P:playbook-notes}}

- **ECS API は 3 GiB と小さい**ためメモリ枯渇が早い。API CPU / メモリの発火では、この余裕の少なさを切り分けの狙いに含める。
- Worker サービスは1つ（`connect-production-worker-service-vvkujofkxht0`）。一次調査の重い `resource_name` からは**除外ジョブ**（`solidqueue::recurringjob` / `activestorage::purgejob`）を外して見る。
- ALB 系の発火では `target_*` と `elb_*` を分けて読む（`elb_4xx` の増加は防御シグナルの可能性）。

---

## {{P:investigation-premises}}

- **ALB は target / elb を分けて解釈する。** `elb_4xx` にはリスナールール「ドメイン以外のリクエストに 403 を返す」設定による直 IP スキャン等の**防御側シグナル**が含まれる。`target_*` が健全なら `elb_4xx` の増減自体は品質劣化を示さない（量と推移のみ確認）。
- **`solidqueue::recurringjob` / `activestorage::purgejob`**（フレームワーク / 定期メンテナンス処理）は、`trace.active_job.perform` の p50 / p95 が長くても ECS Worker / RDS Writer の負荷の直接原因とはみなさない。直接原因の候補は「実際に業務処理を行うジョブ（notification 系・mailer 系・import 系など）」に置く。ただしキュー滞留・Worker スループットの観点では占有時間として影響するため、調査対象からは除外しない。
- **API タスクは 3 GiB と小さくメモリ余裕が少ない**。API メモリの劣化・改善は他プロダクトより小さな変化でも意味を持つ場合がある。

---

## {{P:signal-guide-note}}

`elb_4xx` の増減は防御シグナルとして扱い、`target_*` が健全ならここには載せない。

---

## {{P:signal-rows}}

| API mem peak % | `{{%}}` | `{{%}}` | `{{±ppt}}` | `{{ 閾値 80 / 95 に対する位置付け（3 GiB と小さいので余裕小）}}` |
| Worker mem peak % | `{{%}}` | `{{%}}` | `{{±ppt}}` | `{{ 2 GiB タスク、閾値 80 / 95 }}` |

---

## {{P:ledger}}

| レイヤ | 指標 | 今週 | 先週 | 変化 | monitor発火 | 校正メモ |
| --- | --- | --- | --- | --- | --- | --- |
| SLO | API可用性 SLI（対象週） | `{{%}}` | `{{%}}` | `{{±ppt}}` | `{{発火なし|critical N回 / N分}}` |  |
| SLO | API可用性 EBR 残（対象週） | `{{%}}` | `{{%}}` | `{{±ppt}}` | `{{発火なし|critical N回 / N分}}` | `{{ raw EBR: <value> <unit>（補足） }}` |
| SLO | API可用性 Bad events (raw) | `{{N}}` req | `{{N}}` req | `{{±%}}` | — |  |
| SLO | APIレスポンス SLI（対象週） | `{{%}}` | `{{%}}` | `{{±ppt}}` | `{{発火なし|critical N回 / N分}}` |  |
| SLO | APIレスポンス EBR 残（対象週） | `{{%}}` | `{{%}}` | `{{±ppt}}` | `{{発火なし|critical N回 / N分}}` | `{{ raw EBR: <value> <unit>（補足） }}` |
| SLO | APIレスポンス Bad events (raw) | `{{N}}` req | `{{N}}` req | `{{±%}}` | — |  |
| アプリ | Rails リクエスト数（週計） | `{{N}}` | `{{N}}` | `{{±%}}` | — |  |
| アプリ | Rails p50（週平均） | `{{ms}}` | `{{ms}}` | `{{±%}}` | — |  |
| アプリ | Rails p95（週平均） | `{{ms}}` | `{{ms}}` | `{{±%}}` | — |  |
| アプリ | Rails p95（週中最大） | `{{ms}}` | `{{ms}}` | `{{±%}}` | — |  |
| アプリ | ActiveJob p50（週平均） | `{{ms}}` | `{{ms}}` | `{{±%}}` | `{{発火なし|critical N回 / N分}}` |  |
| アプリ | ActiveJob 処理件数 | `{{N}}` | `{{N}}` | `{{±%}}` | — |  |
| ALB | target 2xx（週計） | `{{N}}` | `{{N}}` | `{{±%}}` | — |  |
| ALB | elb 4xx（週計 / 率） | `{{N}}`（`{{%}}`） | `{{N}}`（`{{%}}`） | `{{±%}}` | — | 防御シグナル含む。量と推移のみ |
| ALB | elb 5xx（週計 / 率） | `{{N}}`（`{{%}}`） | `{{N}}`（`{{%}}`） | `{{±%}}` | `{{発火なし|critical N回 / N分}}` |  |
| ALB | Healthy / Unhealthy host (avg) | `{{N}}` / `{{N}}` | `{{N}}` / `{{N}}` |  | `{{発火なし|critical N回 / N分}}` |  |
| ECS | API CPU max / avg（3 GiB ⚠️） | `{{%}}` / `{{%}}` | `{{%}}` / `{{%}}` | `{{±ppt}}` | `{{発火なし|critical N回 / N分}}` |  |
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
- ALB は `target_*`（アプリ到達 = SLO 主軸）と `elb_*`（ALB レイヤ自身 = 防御シグナル含む）を分けて記録している。`elb_4xx` はリスナールール 403 の防御反応を含むため品質閾値の対象外。`httpcode_target_5xx`（アプリが返した 5xx）は Sentry 管轄のため本表には含まれない。
- SLO Status API は raw bad-event 件数を返さない。別途検証済みの取得元がない場合、Bad events (raw) の今週・先週・変化は `⚠️ 取得不可: Status API は raw bad-event 件数を返さない` とし、raw EBR や SLI から推定しない。
</aside>
