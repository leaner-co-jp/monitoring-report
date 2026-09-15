---
name: weekly-infra-report
description: |
  インフラモニタリング会（モニ会）用の週次レポートを Datadog から生成し、Notion に出力するスキル。LP（リーナー見積）/ PU（リーナー購買）/ FJ（リーナーコネクト）の3プロダクト共通。
  「LP の週次レポートを生成して」「モニ会のレポートを作って」「インフラ週次レポート」と依頼されたときに使用する。対話実行とスケジュール実行の両方に対応する。
---

# インフラモニタリング週次レポート生成

## 利用環境

この skill は特定のエージェント製品の設定ディレクトリに依存しない。実行するエージェントは、この `SKILL.md` を起点に、同じディレクトリの `references/` とリポジトリ内の `templates/`、`docs/` を相対パスで読む。

Datadog と Notion を操作できる接続手段が利用環境にあることを確認してから実行する。ツール名が環境ごとに異なる場合も、ここに示す取得・出力の目的と必須パラメータを満たす同等の手段を使う。

## ゴール

本レポートは **OODA ループの Observe / Orient を厚くまとめ、人間が短時間で Decide / Act に進めること**を目的とする。閾値判定とスパイク検知は Datadog monitor に委譲し、エージェントは monitor の状態とアラート発火を「シグナル」として集める。Observe（事実）と Orient（解釈・先週比・異常検知）を厚く書き、Decide / Act は**候補提示のみ**にとどめる（決めるのは人間）。

判断の軸は **monitor のシグナル**:

- **warning シグナル**: 閾値に接近している予兆。先週からの変化として記録し、傾向を観察する。
- **critical シグナル**: 早急な対応が必要になり得る事象。**単独で報告して終わりにせず、発火したウインドウに絞って原因の主体と上流を掘り下げて調査する**（手順2・4）。

<aside>
💡

ダッシュボード内のノートも参考に。「30日間は長期的なサービスの健全性、7日間は短期的な傾向把握」。SLO は 30d を主軸に見て、バーンレートが1を超えた区間を例示すると、読み手のトレース調査を助ける。

</aside>

## 絶対に守ること

1. **エージェントが独自の閾値を持ち出して判定してはいけない。** 判定材料は monitor の発火とその波及だけ。閾値が必要だと判断したら、レポートに書くのではなく Datadog monitor を作る（`leaner-terraform` の `environments/datadog/`）。
2. **色（🔴🟡🟢⛔）は「読者への要求（対応要否）」にのみ使う。** monitor の発火状況には色を付けず、**件数と継続時間**で書く。
3. **`get_datadog_metric` は先週比トレンドの補足取得専用。** 閾値判定には使わない。
4. **対象ウインドウは直近のクローズ済み7日間。** 週クローズ前（partial-window）では累積系メトリクスを過少計上するため生成しない。
5. Datadog MCP の各呼び出しで `telemetry.intent`（英語・短く・PII なし）を必須指定。

## 構成 — 共通手順 × プロダクト固有値

レポートは**共通部分とプロダクト固有部分を合成して**作る。

| ファイル | 役割 |
| --- | --- |
| このファイル | 全体の骨格と読み込み順 |
| `skills/weekly-infra-report/references/*.md` | 3プロダクト共通の手順 |
| `templates/report.md` | 共通レポートテンプレート（§1〜§3） |
| `templates/<lp\|pu\|fj>.md` | **プロダクト固有値**（変数表 ＋ 差し込みブロック） |

共通側には2種類の差し込み記法がある。どちらも `templates/<product>.md` から値を取る。

- `{{P.xxx}}` — 変数。プロダクト名・サービス名・ID などの単純置換。**表の値はそのまま差し込む literal**（URL やクエリ文字列の中に入るので、装飾やカッコ書きの注記を足さない）。
- `{{P:xxx}}` — ブロック。`templates/<product>.md` の `## {{P:xxx}}` 見出し配下をそのまま差し込む。

**出力に `{{P.` / `{{P:` が1つでも残っていたら合成ミス。** 書き込み前に必ず確認する（`references/output.md` の検証チェック）。

## 読み込み順

**最初に `templates/<product>.md` を読む**（変数とブロックの供給元）。以降は必要になった時点で読む。**全部を先に読まない。**

| いつ | 読むもの |
| --- | --- |
| 開始時（必ず） | `templates/<product>.md` |
| 手順1〜3 に入るとき | `references/collect.md` |
| 手順5 に入るとき | `references/metrics.md` |
| **トリガ ON が確定したときだけ** | `references/investigate.md` ＋ `{{P:domain-notes}}` `{{P:playbook-notes}}` |
| 色を付けるとき | `references/evaluate.md` |
| 書き始めるとき | `templates/report.md` ＋ `references/output.md` |
| メトリクスを取る前（必読） | `docs/datadog-mcp-tips.md` |

トリガ OFF の週は `references/investigate.md` を**読まない**。これがこの分割の主な狙い。

## 全体の流れ

```
0. 対象ウインドウを確定（クローズ済みか確認）          → 下記「ウインドウ」
1. 出力先 DB を作成日時 DESC で確認 → 同名ページがあれば中止 → 下記「重複防止」
2. monitor 状態を一括取得（Observe の主軸）            → collect.md 手順1
3. アラート発火イベントを収集（今週・先週）             → collect.md 手順2
4. SLO の数値を取得                                  → collect.md 手順3
5. アプリ調査トリガを判定                             → collect.md 手順4-a
   └ ON なら investigate.md を読んで発火ウインドウを深掘り
6. インフラ指標の週次値を取得（先週比トレンド用）        → metrics.md 手順5
7. 前週レポートを参照                                → collect.md §0.5
8. 検証チェックを通してから Notion に出力              → output.md §0.9
```

## ウインドウ

対象は **{{P.window_ja}}** の7日間（直近のクローズ済みの週）。

- 今週: `{{period_start}}`（{{P.window_start_ja}}）00:00 JST 〜 `{{period_end}}`（{{P.window_end_ja}}）23:59 JST
- 先週: その前の7日間

Unix timestamp は**必ず JST 基準で算出する**（UTC ずれはウインドウ全体を壊す）:

```bash
python3 -c "import datetime as dt, zoneinfo as zi; jst=zi.ZoneInfo('Asia/Tokyo'); s=dt.datetime(2026,5,27,0,0,tzinfo=jst); e=dt.datetime(2026,6,2,23,59,59,tzinfo=jst); print('F=',int(s.timestamp())); print('T=',int(e.timestamp())); print('PF=',int((s-dt.timedelta(days=7)).timestamp())); print('PT=',int((e-dt.timedelta(days=7)).timestamp()))"
```

`F` / `T` は今週、`PF` / `PT` は先週。調査リンクの `from_ts` / `to_ts` は **epoch ms**（秒を1000倍）なので取り違えない。

## 重複防止（作成より先にやる）

出力先 DB（`{{P.output_db}}`）を作成日時の降順で確認し、対象ウインドウの同名ページが既にあれば**新規作成しない**。その場合は findings のみ報告して終わる。

```sql
SELECT "{{P.title_prop}}", "作成日時"
FROM "{{P.datasource}}"
ORDER BY datetime("作成日時") DESC LIMIT 3
```

⚠️ タイトルプロパティ名はプロダクトで違う（`{{P.title_prop}}`）。

## 出力ページタイトル（固定形式・変更禁止）

```
YYYY/MM/DD - MM/DD {{P.report_title}}
```

可変部は `YYYY/MM/DD - MM/DD` だけ。固定部はスペース・全角文字を含めて変更しない（重複防止の同名判定がタイトル一致に依存している）。
