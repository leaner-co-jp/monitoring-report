# プロダクト別の固定値

各プロダクト固有値ファイル [`templates/<lp|pu|fj>.md`](../templates/) の `{{P:targets}}` ブロックが正。ここは3プロダクトを並べて差分を見るための速読用。**食い違ったら `templates/` を正とし、この表を直す。**

## 共通の構成

3プロダクトいずれも Rails API + ワーカーを ECS Fargate で動かし、Aurora（MySQL）をバックエンドに持つ。ALB 経由でトラフィックを受ける。SLO は「API可用性（30d, target 99.9%）」と「APIレスポンスタイム（30d, target 95%）」の2本、いずれも metric SLO。

## 一覧

| 項目 | LP（リーナー見積） | PU（リーナー購買） | FJ（リーナーコネクト） |
| --- | --- | --- | --- |
| `team` タグ | `lp` | `pu` | **`connect`** |
| ダッシュボード | `nnu-w8q-2yz` | `gbr-uqr-m74` | `bqh-uzk-ipf` |
| SLO API可用性 | `b56ae57a387f51bcb0ac9732cc05718f` | `3997c6b91fde5ac3ac382a13e209a32f` | `8cfdd97cf17c5f768a7d34d09606fa0f` |
| SLO APIレスポンス | `1702a34221e95c85aa455dc43bd216a7` | `34a6197fcb8b569498c42fd5281dffeb` | `78d6959885c65c9f8326ca34e605e32d` |
| APM Rails service | `procurement-api` | `purchasing-api` | `connect-api` |
| APM Worker service | `procurement-worker` | `purchasing-worker` | `connect-worker` |
| ジョブ基盤 | Delayed::Job | Solid Queue（ActiveJob 経由） | Solid Queue（ActiveJob 経由） |
| Worker メトリクス | `trace.delayed_job` | `trace.active_job.perform` | `trace.active_job.perform` |
| ALB タグ | `service:procurement-api, env:production` | `service:purchasing-api, env:production` | `service:connect-api, env:production` |
| RDS クラスタ | `prd-ecs-db-cluster` | `catalog-db-prd` | `rds-connect-production` |
| ECS サービス数 | 4 | 2 | 2 |
| WAF / SES | ダッシュボードに**なし** | ダッシュボードにあるが monitor なし | WAF なし / SES はダッシュボードにあるが monitor なし |
| AWS account | — | `083068756812` | `856251792400` |

## ECS サービス

| プロダクト | 役割 | ECS service 名 | タスクメモリ |
| --- | --- | --- | --- |
| LP | API | `procurement-production-api-service-w0bji1nrnqop` | 8 GiB |
| LP | Worker | `procurement-production-worker-service-gwicbkyhasqz` | 2 GiB |
| LP | Worker-Long | `procurement-production-worker-long-service-ucqjdrqmvu4a` | **1 GiB** ⚠️ |
| LP | Worker-Mailer | `procurement-production-worker-mailer-service-bsk312etaj9j` | **1 GiB** ⚠️ |
| PU | API | `purchasing-production-api-service-t7be14m1403n` | 8 GiB |
| PU | Worker | `purchasing-production-worker-service-ydlu96mimsfg` | 2 GiB |
| FJ | API | `connect-production-api-service-vqce1bfa4dby` | **3 GiB** ⚠️ |
| FJ | Worker | `connect-production-worker-service-vvkujofkxht0` | 2 GiB |

---

## プロダクト固有の既知事項

読み飛ばすと誤った原因分析をする箇所。

### LP（リーナー見積）

1. **ダッシュボードに WAF / SES セクションがない。** レポートにも書かない。
2. **Delayed::Job のメトリクス名は `trace.delayed_job`。** `trace.delayed_job.*` というサブスペース付きは存在しない（「単一スパン」タイプ）。
3. **Worker-Long / Worker-Mailer はタスクメモリ 1 GiB と小さい。** メモリ枯渇のリスクが相対的に高く、% ベースで見ると実際より高めに見える。Worker-Long は max% で1週間に4回以上のスパイクや 70% 超えが見えたら増額検討を Decide 候補に入れる。
4. **外部ワークロードで実行される図面系ジョブの扱い（重要）**

   `DetectDrawingReferenceJob` と `GenerateDrawingFileThumbnailsJob` は実行時間が長く見えるが、**重い処理の実体はリーナー見積のインフラ外にある外部ワークロードで実行されている**。

   したがってこれらが `trace.delayed_job` の p95 / duration や重い `resource_name` の上位に出ても、**ECS Worker の CPU / メモリや RDS Writer CPU / コネクションの直接原因とはみなさない**。長い p50 は外部ワークロード待ちである。

   RDS Writer CPU / ECS Worker の critical・warning の因果を書くときは、直接原因の候補を「**リーナー見積側で実際に DB 書き込み・処理を行うジョブ**（compress 系など）」に置く。

   この切り分けは詳細トレース調査だけでなく **§1 の総合ステータスと §2.x の Orient にも一貫して明記する**（3プロダクトとも同じ節番号。§2 冒頭の「調査時の前提」にも明記してある）。

   ただし**キュー滞留や Worker スループットの観点ではキューを占有する時間として影響し得る**ため、滞留系のシグナルが鳴った場合の一次調査対象からは除外しない。

### PU（リーナー購買）

1. **Worker は Solid Queue（ActiveJob 経由）。** メトリクスは span 名込みの `trace.active_job.perform{service:purchasing-worker,env:production}` を使う。`trace.active_job{...}`（span 名なし）や `trace.solid_queue.*` は**使わない**。
2. **調査除外ジョブ**: `solidqueue::recurringjob` / `activestorage::purgejob` はフレームワーク・定期メンテナンス系として、劣化ジョブ表・Decide 候補・原因調査対象から除外する（取得値が重く見えても除外）。
3. **ダッシュボードに WAF / SES セクションはあるが monitor がない。** monitor 駆動の本レポートでは扱わない（シグナルソースがないため）。扱いたければ monitor を追加してから取り込む。
4. **RDS Reader がほぼ未活用。** 「読み取りクエリ分散検討」を低優先 Decide 候補として残す。Reader には専用 monitor がないため**判定対象外**とし、参考値として記載する。
5. LP と異なり Worker-Long / Worker-Mailer の monitor は存在しない。
6. 劣化ジョブの仮説の型: mailer 系は送信件数依存、import 系はデータサイズ依存。

### FJ（リーナーコネクト）

1. **API タスクメモリは 3 GiB**（LP・PU の 8 GiB より小さい）。同じ閾値（80 / 95）でも余裕が小さく、急なピークが致命傷になりやすい。**API メモリは特に注視する**。
2. **Worker は Solid Queue（ActiveJob 経由）。** PU と同じく `trace.active_job.perform{service:connect-worker,env:production}` を使う。除外ジョブも PU と同じ。
3. **WAF はない。SES セクションはあるが monitor がない**ため扱わない。
4. **ALB は target / elb を分けて解釈する（FJ 固有）**

   `httpcode_target_*xx`（アプリ到達）が SLO / 品質判定の主軸。`httpcode_elb_*xx`（ALB レイヤ自身）には、リスナールール「ドメイン以外のリクエストに 403 を返す」設定による**直 IP スキャン等の防御側シグナル**が含まれる。

   したがって `elb_4xx` は品質閾値の対象にせず、**量と推移のみ確認**する。target_* が健全なら elb_4xx の増減自体は品質劣化を示さない。ALB 5xx monitor の numerator は `elb_5xx`（インフラ層のタイムアウト・502 等）。

5. **RDS Reader がほぼ未活用**（PU と同様の扱い）。
6. **ダッシュボード全体は約 61k 文字**で MCP 応答上限を超える。構成差分検知はフル取得せず、必要な widget に絞る。
7. 劣化ジョブの仮説の型: notification 系は SES 送信・attachment 参照依存、import 系はデータサイズ依存。劣化エンドポイントは ZIP 生成・S3 取得も候補。

---

## 3プロダクト共通の棲み分け

- **アプリ起因の 5xx は Sentry 管轄。** 本レポートの ALB は `httpcode_elb_5xx`（インフラ層: タイムアウト / ヘルシーホスト無し / 502 など）のみを扱い、`httpcode_target_5xx`（アプリが返した 5xx）は**二重監視を避けるため意図的に扱わない**。
- **Rails レイテンシの恒常ドリフトは SLO（APIレスポンスタイム）と Sentry に委譲。** monitor の直接閾値がない指標なので、Rails レイテンシ単体では対応要否を判定しない。
- **forecast（キャパシティ予測）は週次レポートで扱わない。** 精度の問題から月次など別頻度に分離する。
