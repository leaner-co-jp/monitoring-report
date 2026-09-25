# レポートの書き方

[`skills/weekly-infra-report/references/output.md`](../skills/weekly-infra-report/references/output.md)（出力ルール・日本語表現・検証チェック）と [`templates/report.md`](../templates/report.md) の運用ガイドに対応。3プロダクト共通。

## 出力ルール

- **数値はすべて単位付き**（ms, %, req, MiB / GiB）。
- 比較は「**今週: X / 先週: Y / 差分: ±Z（±W%）**」の形。
- 推測・主観は `(推定)` を付けて事実と分離する。
- データ取得に失敗した場合は `⚠️ 取得不可: <理由>` と明示する（**省略不可**）。
- ステータス絵文字には必ず根拠の数値を併記する（絵文字単体は不可）。
- **色（🔴🟡🟢⛔）は「読者への要求（対応要否）」にのみ使う。monitor の発火状況には色を付けない** — 発火は件数と継続時間で書く。判定の当て方は [monitors.md](monitors.md)。

## 自然な日本語で書く

英語・カタカナの直訳調を避け、読み手が日本語として無理なく読める表現にする。**技術用語を無理に訳す必要はない** — severity の語（warning / critical）や固有名詞（monitor 名・メトリクス名・`resource_name`）はそのまま使ってよい。狙いは**地の文が英語直訳調にならないこと**。

ただし monitor の**状態語**（OK / Warn / Alert）は台帳・本文では使わない（`発火なし` / `critical 1回 / 10分` のように事実で書く → [monitors.md](monitors.md)）。

| 避ける表現 | 使う表現 |
| --- | --- |
| sustained peak (1h) / 1h sustained peak | 1時間平均の持続ピーク／1時間平均でならした持続的なピーク |
| sustained は低位 | 持続的な使用率は低位 |
| sustained な劣化 | 持続的な劣化 |
| critical 閾値をクロス / critical をクロス | critical 閾値を超過／突破 |
| 瞬間バースト / 大量バースト | 瞬間的な集中／短時間に大量実行 |
| latency は…と軽く | 処理時間は…と軽く |

## Orient の書き方

- **悪化の「主体」と「上流原因」を分けて書く。** 因果は両方向あり得る（DB が遅い → API CPU が上がる／ジョブが重い → Worker メモリが膨らむ）。一次調査で主体を、相関チェックで上流原因を当てる。
- **瞬間スパイクか持続的な劣化かを必ず切り分ける。** `.rollup(avg, 3600)` の持続ピークと素の瞬間ピークは別物（[datadog-mcp-tips.md](datadog-mcp-tips.md) 罠3）。
- **複数の monitor が同時刻に鳴っていたら束ねる。** 同一インシデントの別側面である可能性が高いので、1つの原因仮説にまとめる。
- **p99 だけ伸びる = テール劣化 / 全体がシフト = 負荷増**、と切り分ける。
- **分母を必ず確認する。** 「p95 +20%」がトラフィック +40% 由来なのかを、リクエスト数・ジョブ件数で判別する。
- SLI / EBR は SLO Status API で対象週・先週の同じ7日間を取得し、差を percentage point で示す。Status API は raw Bad events 件数を返さないため、別途検証済みの取得元がなければ取得不可とし、raw EBR や SLI から推定しない。
- ダッシュボードノートの推奨: **EBR が 20% を下回ったら「原因調査中」**とし、機能開発より信頼性回復を優先する。今週の EBR をこの閾値と比べて評価する。
- バーンレート > 1 の区間があった場合は、その時間帯のトレース調査を推奨として書く。

## 調査リンク規約

site は `app.datadoghq.com`、markdown の `[ラベル](URL)` 記法。`{{F}}` / `{{T}}` は今週の epoch ms、`{{incident}}` はインシデント時刻の epoch ms。

| 用途 | 使うリンク |
| --- | --- |
| 期間レンジを見せる | `/dashboard/<dashboard_id>?from_ts={{F}}&to_ts={{T}}` |
| 特定インシデント時刻の点的調査 | `/apm/traces?query=…&end={{incident}}&paused=true`（15分ウインドウ） |
| 週全体で重い endpoint / resource を順位付け | `/apm/services/<service>?env=production&start={{F}}&end={{T}}` |

⚠️ `/apm/traces` は広い `start` を無視して end − 15分にクランプする。**週レンジには使わない。**

### monitor は名前・リンク・ID の合わせ技で書く

```
[<monitor 名>（#{{monitor_id}}）](https://app.datadoghq.com/monitors/{{monitor_id}})
```

例: `[RDS Writer CPU monitor（#297262491）](https://app.datadoghq.com/monitors/297262491)`

本文で monitor に言及するとき、`mon 12345` のような **ID 単独の略記は使わない**。必ずこの形にして「クリックできる・一意に特定できる・人間が読んで分かる」の3点を満たす。

### Datadog が生成したリンクを優先する

アラートイベント本文の埋め込みリンクと、`get_datadog_metric` 応答の `metrics_explorer_url` は **Datadog 生成のため再利用が最も安全**。手組みより優先する。

## レポートの章構成

**3プロダクトとも同一構成（v2 / イベント駆動 + 台帳）。** LP は 2026-08-21、PU は 2026-08-26、FJ は 2026-08-27 に移行済み（[templates/lp-template-revised.md](templates/lp-template-revised.md)）。旧 v1（レイヤ別網羅の5セクション）は全プロダクトで廃止済み。

### 3プロダクト共通（v2 / 3セクション）

```
1. 🎯 総合評価                      ← 必読。常に存在
   - 色の意味（固定文。🔴🟡🟢⛔ = 読者への要求。monitor 発火には色を使わない）
   - 評価ルール（固定文。総合ステータスの判定手順1〜4。結果は絵文字ではなく「今週中に人の判断が必要」等の言葉で表す）
   - 総合ステータス（地の文1段落。判定色+一言／発火概要／SLO等への波及／なぜその色か／発火内訳／ユーザー影響／monitor状態／トラフィック先週比）
   - アプリ調査トリガ ON/OFF と根拠
   - 今週のシグナル変化: critical / warning / monitor 以外で動いた指標
   - 先週比の主要変化（表。§3.1 台帳からの抜粋）
   - Decide / Act 候補: 🔴 緊急（今週中に決める）/ ⛔ 滞留（3週以上）/ 🟡 要検討（次週も再発したら）/ 🟢 継続観察 / ℹ️ 恒久課題
   - 報告の結び（総合ステータスを再度要約し「全体報告はここで終了」と宣言。実際に存在する節（§2/§3）だけを詳細確認用として案内）
2. 🔍 調査                          ← monitor 発火があった週のみ存在
   2.x インシデント単位で1節（レイヤ別に分けない）
       シグナル → 一次調査 → 相関調査 → Orient → Decide/Act → 調査リンク
3. 📎 付録（記録用）                 ← 読ませない
   前回 Decide / Act の反映状況（解消・改善もここに書く）
   3.1 全指標の週次記録（台帳 = 数値の唯一の住所。「校正メモ」列つき）
   3.2 取得時刻・期間 / 3.3 今週の取得上の注記
```

発火が一つもない週は **§2 が見出しごと存在しない**。数値は発火の有無に関わらず §3.1 の台帳に毎週記録する。
「今週の確認範囲」「網羅性」チェックリストは 2026-08-24 に §1 から撤去（差分は [templates/lp-template-revised.md](templates/lp-template-revised.md) 参照）。

**PU は 2026-08-26、FJ は 2026-08-27 に上記構成へ移行**。旧方式では両プロダクトとも「評価色 = monitor 状態にそのまま一致」だったが、v2 移行で LP と同じ「色 = 対応要否のみ、発火状況には色を付けない」ルールに統一した。

プロダクト固有の違い:
- **PU**: Worker が1サービスのみ（LP は API/Worker/Worker-Long/Worker-Mailer の4つ）。除外ジョブは `solidqueue::recurringjob` / `activestorage::purgejob`（フレームワーク/定期メンテナンス系）。
- **FJ**: Worker が1サービスのみ。除外ジョブは PU と同じ。**API タスクメモリが 3 GiB**（LP・PU の 8 GiB より小さく、閾値は同じでも余裕が少ない）。**ALB は `target_*`（品質判定の主軸）と `elb_*`（防御シグナル含む）を分けて評価する**固有ルールがある — リスナールールで直 IP スキャン等に 403 を返す構成があり、`elb_4xx` の増減は品質劣化を意味しない。

### 劣化・改善の判定基準（§2.x の調査表）

- **劣化**: ウインドウ内 p50 が平常比 **+50% 以上** または **+500ms 以上**
- **改善**: p50 が先週比 **-30% 以上** または **-500ms 以上**

重い `resource_name` は Top 15（`by {resource_name}` で `aggregator="avg"`、p50 降順）。PU / FJ は `solidqueue::recurringjob` と `activestorage::purgejob` を除外する。

## 出力時に必ず除外するもの

[`templates/report.md`](../templates/report.md) から生成するとき、以下はレポートに含めない:

1. `templates/report.md` 冒頭の運用ガイド（トグル）
2. テンプレートの methodology 前置き（「monitor 駆動の OODA レポート…」等の枕文）
3. 「ガイド:」で始まる記入指示、書き方だけを指示する注記（例「トリガ ON の週のみ実施」）

**残すもの**: ドメイン文脈を伝える注記は中身なので残す。具体的には Sentry 棲み分けと IOPS 注意（§2 冒頭の「調査時の前提」と §3.1 の注記）、FJ の elb 防御シグナルの説明。

出力はタイトル行（`# …`）から開始し、前置きの引用文を付けずそのまま `## 1` へ続ける。
