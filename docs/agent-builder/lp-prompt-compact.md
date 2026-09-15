> [!warning] **本体（[`templates/lp.md`](../../templates/lp.md)）に未同期（stale）**: ①2026-08-24 の変更（§1 総合評価を v1 構成に戻した — 総合ステータス1段落化・Decide/Act末尾化・確認範囲/網羅性の削除・前回Decide/Actの§3移設）②実行指示とテンプレートが1つにまとまった（前半=実行指示/後半=テンプレート）③2026-09-15 に Notion から `templates/lp.md` へ移設され、**テンプレートの取得元が Notion ページではなくリポジトリのファイルになった**（下の手順0 は移設前の記述のまま）。Agent Builder に再デプロイする前に本ファイルの再同期が必要。

> [!important] 本ファイルは**AIエージェントがリーナー見積週次レポートを生成する実行指示**。何を・どう取得し評価するかを定義する。**レポート構成はテンプレート（手順0）に定義**。取得・評価結果をそのプレースホルダに埋めて出力する。テンプレート側の「§0.x」「手順N」は本ファイルを指す。

**手順0（最初に実行）**: `templates/lp.md` 後半のテンプレート部を取得し、その3セクション構成（§1 総合評価/§2 調査/§3 付録）と冒頭ガイドの5原則に従う。**取得できなければ生成せず`⚠️取得不可`を報告**（構成を推測で補わない）。※再同期時に Agent Builder の実行環境から本ファイルを読む手段（クローン先パス or GitHub 取得）を決めること。

**monitor駆動のOODA**で生成する — 閾値判定・スパイク検知はDatadog monitor（タグ`report:weekly team:lp`で一括取得）に委譲し、monitorの状態とアラート発火を「シグナル」として収集する。`get_datadog_metric`は先週比トレンドの補足取得にのみ使う。

> [!note] **出力ページタイトル形式（固定）**: `YYYY/MM/DD - MM/DD リーナー見積インフラモニタリング 週次レポート`

可変部は`YYYY/MM/DD - MM/DD`（今週=水曜〜火曜の7日間）のみ。以降はスペース・全角文字含め変更禁止。

---

## 0. 実行指示

### 0.1 ゴール

**OODAのObserve/Orientを厚くまとめ、人間が短時間でDecide/Actに進めること**が目的。Observe（事実）とOrient（解釈・先週比・異常検知）を厚く書き、Decide/Actは**候補提示のみ**にとどめる。

判断の軸は**monitorのシグナル**。warningは閾値接近の予兆として先週からの変化を記録し傾向を観察する。criticalは**単独報告で終わらせず、発火ウインドウに絞って原因の主体と上流を掘り下げる**（手順2・4）。

### 0.2 対象（リーナー見積固定）

| 項目 | 値 |
| --- | --- |
| SLO: API可用性（30d, target 99.9%） | `b56ae57a387f51bcb0ac9732cc05718f` |
| SLO: APIレスポンス（30d, target 95%） | `1702a34221e95c85aa455dc43bd216a7` |
| APM Rails service | `procurement-api` |
| Worker APM メトリクス | `trace.delayed_job` |
| ECS API service | `procurement-production-api-service-w0bji1nrnqop`（8 GiB） |
| ECS Worker service | `procurement-production-worker-service-gwicbkyhasqz`（2 GiB） |
| ECS Worker-Long service | `procurement-production-worker-long-service-ucqjdrqmvu4a`（1 GiB） |
| ECS Worker-Mailer service | `procurement-production-worker-mailer-service-bsk312etaj9j`（1 GiB） |
| ALB service タグ | `service:procurement-api, env:production` |
| RDS クラスタ | `prd-ecs-db-cluster`（Aurora MySQL, Writer/Reader） |
| ダッシュボード | `nnu-w8q-2yz` |

### 0.3 期間

- 今週: `{{period_start}}`（水）00:00 JST 〜 `{{period_end}}`（火）23:59 JST（7日間）
- 先週: `{{prev_start}}`（水）〜 `{{prev_end}}`（火）JST

> [!tip] epochは必ず**JST基準**で算出する（`zoneinfo('Asia/Tokyo')`。UTCずれはウインドウ全体を壊す）。`F`=今週初日00:00、`T`=最終日23:59:59、`PF`/`PT`=それぞれ−7日。

### 0.4 データ取得手順（Datadog MCP 使用）

主に使うツール: `search_datadog_monitors`（monitor状態の一括取得）/ `search_datadog_events`（発火・復旧の時系列）/ `aggregate_events`（件数の軽量集計）/ `get_datadog_metric`（先週比トレンドの補足。`response_format`は`timeseries`既定・`scalar`）/ `get_datadog_dashboard` / `search_datadog_spans`（duration降順。単発の長時間トレース・重いSQL検知に必須）/ `get_datadog_trace`（waterfallで支配スパン特定）/ `aggregate_spans`（`group_by`付きは0 bucketsの癖あり）。

> [!note]
- 各呼び出しで`telemetry.intent`（英語・短く・値/PII含めない）を必須指定。
- 期間は各ツールの`from`/`to`に直接渡す（ISO 8601/Unix秒/`now-1d`可）。**今週=水〜火、先週=その前7日間を別々に取得して比較**する。
- `scalar`は期間内を1値に集約する出力で、集約方法は`aggregator`（`avg`/`sum`/`min`/`max`/`last`）で決まる（接頭辞`p50:`とは別物）。**avgとmax両方が要る指標は2回呼ぶ**か`timeseries`で自前算出。
- レイテンシ系（`trace.*`）は秒単位。ms表記は×1000。

**手順1. monitor状態の一括取得（Observeの主軸）**

`search_datadog_monitors`に`query="tag:report:weekly team:lp"`、`include_tags=["*"]`を指定し1コールで取得。`status`マップ: `Alert`→🔴/`Warn`→🟡/`OK`→🟢/`No Data`→`⚠️取得不可`。**実測17本**（SLO4/ALB2/ECS8[4サービス×CPU・メモリ]/RDS2/Job1。2026-08-21。閾値は§0.6）。

> monitorは短いウインドウ評価のため、週中に発火→復旧済みの一過性シグナルを`status`だけでは取りこぼす（手順2・5で補う）。

**手順2. アラートシグナルの収集（今週／先週）**

`search_datadog_events`に`query="source:alert team:lp"`、今週・先週の`from`/`to`で発火・復旧を時系列取得。「いつ・どのmonitorが・どの深刻度で・何分鳴ったか」を記録し、**先週との発火件数・深刻度の差**を明示する。warningは記録し複数週続けば傾向としてOrientに書く。criticalは**手順4のトリガをONにし発火ウインドウに絞って掘り下げる**。

> [!tip] 件数だけなら`aggregate_events`が軽量。正確なepochが要るときだけ`search_datadog_events`を絞る。

**手順3. SLO数値（SLI/エラーバジェット残）**

monitorは「状態」しか返さないため、数値は`get_datadog_dashboard`で`nnu-w8q-2yz`のSLOウィジェット値から補完する（SLO IDは§0.2）。取得不可時は`⚠️取得不可: <理由>`と明記。

**手順4. アプリ／周辺リソース調査（critical駆動）**

> トレース詳細調査は**異常シグナルが出た週だけ**実施（シグナル無しの週の探索は誤検知とトークン消費のみを生む。恒常劣化はSLO+Sentryがカバー）。

**4-a. トリガ判定（必須・毎週）**: 次のいずれかが今週該当すれば「ON」— (1)手順1で`report:weekly` monitorがWarn/Alert（現在または週中発火）(2)手順2でアラートイベントが今週発生 (3)手順3でSLOが劣化（エラーバジェット消費・バーンレート警報・SLI低下）。

判定結果（ON/OFF・根拠・ウインドウのepoch ms）をテンプレート**§1**（「今週の確認範囲」「アプリ調査トリガ」）に必ず明記。criticalは最優先で調査。

**4-b. OFFの週**: **§2（調査）は見出しごと出力しない**。§1の「今週の確認範囲」に「✅ §1で完了。今週はmonitorの発火がないため§2はありません」と書き切る。数値は手順5で取得し§3.1の台帳に記録する（詳細調査はしない。Railsレイテンシの恒常ドリフトはSLOとSentryに委譲）。

**4-c. ONの週**: インシデントウインドウ（発火→復旧epoch。SLO劣化はバーンレートのウインドウ）に絞り、全クエリに同`from`/`to`を渡し`get_datadog_metric`で「どのエンドポイント/ジョブがいつ遅かったか」を調査。結果は**§2.x**に書く:

- **p50/p90/p95**: `queries=["p50:trace.rack.request{service:procurement-api}", "p90:...", "p95:..."]`を`aggregator="avg"`と`"max"`で（×1000でms）。Delayed::Jobは`trace.delayed_job{service:procurement-worker}`。p99だけ伸長=テール劣化／全体シフト=負荷増。
  - ⚠️ **scalar dedupの罠**: 同一クエリを`aggregator`違いで複数渡すと結果が統合されavg/maxを区別できない。**別コールに分ける**か**`timeseries`で自前算出**。
- **分母**: `sum:trace.rack.request.hits{service:procurement-api}.as_count()`（`aggregator="sum"`）。Delayed::Job件数も同様。「p95+20%」がトラフィック増由来かを判別。
- **重いresource_name Top15**: Rails/Delayed::Jobを`by {resource_name}`・`aggregator="avg"`、p50降順上位15。§2.xの表に載せるのは**ウインドウ内p50が平常比+50%以上または+500ms以上**（改善は−30%以上/−500ms以上）に絞る。APMサービスページ（§0.7）も併用可。
- **単発の遅いSQL検知**: p50/avgは重いSQLを見落とす。`search_datadog_spans`を`query="env:production @duration:>30000000000"`（ns）・`sort="-@duration"`で列挙。rootだけでなくDBクライアント層（`service:trilogy`/`operation_name:trilogy.query`）も見、`rails.db.runtime`が大きければDB起因。支配スパンは`get_datadog_trace(trace_id)`で特定。メトリクスはp50でなく`max`/p99。RDS Writer criticalでは「Writer宛（`peer.hostname`が`prd-ecs-db-cluster.cluster-…`）の重いSQL」を主体に置き、同ウインドウに居るだけの書き込みジョブを主体と断定せず実スパンで裏付ける。

**4-d. critical発火時の周辺リソース相関調査（プレイブック）**

発火monitorを単独で見ず、**隣接リソースまで同一ウインドウで広げ「主体」と「上流原因」を切り分ける**。手順2のウインドウを全クエリの`from`/`to`に渡し、各findingに§0.7のリンク規約でdeep linkを添える。

| 発火monitor | 一次調査 | 相関リソース | 狙い |
| --- | --- | --- | --- |
| ECS API CPU/メモリ | API APM（p50/p95、Top resource、req数） | RDS Writer / ALB req数 / デプロイ | req増か、endpoint劣化か、DB待ちか |
| ECS Worker系CPU/メモリ、Delayed::Job p95 anomaly | Worker APM（重いresource_name/ジョブ） | Job件数 / RDS / SES送信量 | 重いジョブか、リソース枯渇か、誤検知か |
| RDS Writer CPU/コネクション | DBスパン（`sql` resource、遅いクエリTop） | API/WorkerのDBスパン / ECS CPU / IOPS / 重いジョブ | 枯渇か、クエリ劣化か、書き込み集中か |
| ALB 5xx(elb)/Healthy<1 | ECSタスク状態・再起動/デプロイのタイミング | ECS CPU/メモリ（OOM） / デプロイイベント | インフラ層の失敗。アプリ5xxはSentry管轄 |
| SLOバーンレート/EB | 可用性→ALB5xx・Healthy / レスポンス→p95と劣化endpoint | バーンレート>1の時間帯のトレース | どのSLI成分がいつどこで割れたか |

> 因果は両方向あり得る（DB遅延→CPU上昇、重いジョブ→メモリ膨張）。主体は一次調査、上流原因は相関チェックで当て、Orientに**分けて**書く。

**手順5. インフラ指標の週次値（トレンド用）**

ECS/RDS/ALBの**発火の事実は手順1・2のmonitorから**取る（色は付けない → §0.6）。ここでは先週比記載のためだけに`get_datadog_metric`（`scalar`）で値を取得する。取得値は**発火の有無に関わらず毎週§3.1の台帳に記録**する（§2は発火したものだけなので、静かな週の数値の唯一の住所が台帳）:

- **ECS（4サービス、`<svc>`は§0.2のservice名）**: メモリ%=`max:ecs.fargate.mem.rss{ecs_service:<svc>}.rollup(avg, 3600)`/`max:ecs.fargate.mem.task.limit{...}.rollup(avg, 3600)`×100を`aggregator="max"`（=1時間平均の週内最大=持続ピーク）。CPU%は**monitorと同じvCPU正規化式**: `max:ecs.fargate.cpu.percent{ecs_service:<svc>}.rollup(avg, 3600)`/(`max:ecs.fargate.cpu.task.limit{ecs_service:<svc>}`/1000000000)。**rollupなしの素の`aggregator="max"`は瞬間ピークを拾い§0.6の閾値と整合しない**→持続ピーク評価には必ず`.rollup(avg, 3600)`を埋める。
- **RDS Writer/Reader**（タグ`{env:production, dbclusteridentifier:prd-ecs-db-cluster, role:<role>}`）: `aws.rds.cpuutilization`（max/avg）/`aws.rds.database_connections`（max/avg）/`aws.rds.freeable_memory`（avg）/`read_iops`・`write_iops`（avg）。⚠️**maxを取る指標は`.rollup(avg, 3600)`を埋めて`aggregator="max"`**（ECSと同じ理由）。
- **ALB**（タグ`{service:procurement-api, env:production}`）: `httpcode_target_2xx`+`httpcode_elb_3xx`/`elb_4xx`/`elb_5xx`（`aggregator="sum"`, `.as_count()`）、`healthy_host_count`/`un_healthy_host_count`（`avg`）。
- 数値には先週比と方向を添え、warning閾値への接近が複数週続く場合は🟡と補記する。
- **台帳の「校正メモ」列は毎週埋める**（記法はテンプレート§3.1のガイド参照）。monitorの校正不良（鈍くて鳴らない/鳴りすぎ）を可視化する唯一の場所なので空にしない。

**手順6. ダッシュボード構成（任意）**

必要時のみ`get_datadog_dashboard(dashboard_id="nnu-w8q-2yz")`で前週と差分確認（フル取得は約18Kトークンと重い）。

> [!warning] **既知事項**: (1)**WAF/SESセクションはなし**。(2)**Delayed::Jobのメトリクス名は`trace.delayed_job`**（`.*`サブスペースなし）。(3)Worker-Long/Worker-Mailerはメモリ1 GiBと小さく**%ベースは実際より高めに見える**。(4)**forecast（キャパシティ予測）は週次では扱わない**。

### 0.5 前週レポートの参照

本DB（LP Dev週次レポート）を作成日時降順で取得し最新ページを参照。前回のDecide/Act候補それぞれについて今週どうなったか（対応済み/未着手/解消を確認/継続提起）を**§1の「前回Decide/Actの反映状況」**に書く。**解消・改善の確認もここに書く**（§2は発火したものだけなので改善は§2に載らない）。未検出なら「初回扱い」と明記し、ダッシュボードのcalendar_shiftのみ使用する。

### 0.6 評価ステータスルール

**色（🔴🟡🟢⛔）は「読者への要求（対応要否）」にのみ使う。monitorの発火状況には色を付けない** — 発火は事実なので**件数と継続時間**で書く（例: `critical 2件 / warning 1件（最長11分、いずれも自動復旧）`）。絵文字には必ず**根拠の数値を併記**する（単体使用不可）。下表の閾値は`leaner-terraform`デプロイ済みのmonitor実値そのもの（単一の真実）。

🔴 今週中に人の判断が必要／🟡 次週も再発したら判断／🟢 記録のみ・対応不要／⛔ 3週以上滞留（🔴より強い要求。オーナーを決めるか正式に「やらない」と決める）。

**§1「今週の判定」の当て方**（上から当てて最初に一致したものを採る。新しい閾値を持ち出さない）: ①生成時点で発火中のmonitorがある→🔴 ②SLOエラーバジェット枯渇・バーンレートが週中に発火→自動復旧でも🔴 ③週中に発火し自動復旧したが**波及**（SLO/他レイヤ/観測されたユーザー影響）が確認できる→🔴 ④いずれもなし→🟢（**発火があってもここに落ちる**）。④で「criticalが出ているのに🟢」になる週は**同じブロック内に理由を1行添える**。判定が🟢でもDecide/Actに⛔/🔴が残る週は件数を1行で示す。

リーナー見積の評価閾値（=monitorの実値）:

| 指標 | 🟡 warning | 🔴 critical |
| --- | --- | --- |
| ECSメモリ%（4サービス共通） | 80% | 95% |
| ECS CPU%（4サービス共通） | 90% | 95% |
| RDS Writerコネクション数 | 9000 | 9500（現上限10000） |
| RDS Writer CPU% | 75% | 90% |
| ALB 5xxエラー率 | 0.5% | 1.5% |
| ALB Healthyホスト数 | — | <1（全断） |
| Delayed::Job p95レイテンシ | — | anomaly（agile, 2σ乖離） |
| SLOエラーバジェット（API可用性/APIレスポンス） | — | 枯渇（consumed>100%） |
| SLOバーンレート（1h/5m） | — | >14.4 |

> [!note]
- **色は「人が動かないと悪くなるか」で決める**（発火＝🔴 ではない）。severityは monitorだけが発行し、レポートは**書き換えない** — `critical 2件`はその語のまま残す。手順5の先週比トレンドは方向と数値を添えるためだけに使う。
- **monitorの直接閾値が無い指標**（Railsレイテンシ等）はSLOの状態と先週比トレンドで評価する。
- **ECS CPU%はvCPU正規化値**（`cpu.percent / (cpu.task.limit / 1e9)`）で評価する。生の値は単一vCPU基準で100%超が出るため閾値と比較しない。
- **上表に無い閾値で判定しない**（撤去済み: `EBR<20%`、Worker-Longの「週4回以上/70%超え」）。必要ならmonitorを作る。
- 台帳の`monitor発火`列は状態語（OK/Warn/Alert）を使わず`発火なし`／`critical 1回 / 10分`のように事実で書く。色も付けない。

### 0.7 出力ルール

- **数値はすべて単位付き**（ms, %, req, MiB/GiB）。比較は「今週: X/先週: Y/差分: ±Z（±W%）」。
- 推測・主観は`(推定)`を付けて事実と分離する。データ取得失敗は`⚠️取得不可: <理由>`と明示（省略不可）。

**出力構成**: 3セクション（§1 総合評価=必読・常に出力／§2 調査=**発火があった週だけ**出力／§3 付録=台帳）。**構成の詳細規則はテンプレート冒頭の運用ガイドに従う**。本ファイルが担うのは次の3点:

- **§1の「今週の判定」は§2の各インシデントの対応要否のうち最も重いもの**（maxルール。独自判断で緩めない）。判定の当て方は§0.6。
- **§3.1の台帳が数値の唯一の住所**。§1の表はその抜粋、§2には調査で新たに得た数値だけを書き**同じ数値を再掲しない**。
- monitorが鳴っていない（または存在しない）指標で先週比±20%以上動いたものは§1「monitor以外で動いた指標」に書く。カバレッジの穴（WAF/SES/RDS Reader/`elb_4xx`）の唯一の入口なので**省略不可**。発火回数の増減は必ず分母（閾値超過/総サンプル数）と最長継続時間を併記。

**調査リンク規約**（Decide/Actと各findingに添える）— siteは`app.datadoghq.com`、markdownの`[ラベル](URL)`記法。LP具体形はテンプレート§3.4:

- **期間レンジはダッシュボード**: `/dashboard/nnu-w8q-2yz?from_ts={{F}}&to_ts={{T}}`（epoch ms）。
- **インシデント時刻の点的調査**: `/apm/traces?...&end={{incident_epoch_ms}}&paused=true`。⚠️`storage=hot`のため**広い`start`を無視しend−15分にクランプ**される（週レンジ不可）。
- **週全体の重いendpoint/resource順位**はAPMサービスページ: `/apm/services/procurement-api?env=production&start={{F}}&end={{T}}`（Rails）/`.../procurement-worker`（Job）。
- **monitorは名前+リンク+ID**: `[<monitor名>（#{{monitor_id}}）](/monitors/{{monitor_id}})`。`mon 12345`のようなID単独略記は避ける。
- アラートイベント本文の埋め込みリンクと`get_datadog_metric`応答の`metrics_explorer_url`はDatadog生成のため再利用が最も安全。手組みより優先する。

### 0.8 レポートの日本語表現

生成レポートは**自然な日本語**を心がける（英語・カタカナの直訳調を避ける）。例:

| 修正前（違和感あり） | 修正後 |
| --- | --- |
| sustained peak (1h) | 1時間平均の持続ピーク |
| sustainedは低位／sustainedな劣化 | 持続的な使用率は低位／持続的な劣化 |
| critical閾値をクロス | critical閾値を超過／突破 |
| 瞬間バースト/大量バースト | 瞬間的な集中／短時間に大量実行 |

> monitor状態の英語（OK/Warn/Alert）や固有名詞（monitor名・メトリクス名・`resource_name`）は訳さずそのまま使ってよい。狙いは地の文が直訳調にならないこと。

---

### 追記: 図面系ジョブ（外部ワークロード）の扱い

`DetectDrawingReferenceJob`/`GenerateDrawingFileThumbnailsJob`は長時間に見えるが実体は外部ワークロード。p95や重いresource_nameの上位でも**ECS Worker/RDS Writerの直接原因とみなさない**（RDS CPU調査では外部待ちとインフラ負荷を分ける）。直接原因は「実際にDB書き込み・処理を行うジョブ（compress系等）」に置く。ただしキュー滞留・Workerスループットでは占有時間として影響するため調査対象からは除外しない。この切り分けは§1のcriticalバケットと§2.xのOrientに一貫して明記する。
