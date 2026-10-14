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

ダッシュボード内のノートも参考に。「30日間は長期的なサービスの健全性、7日間は短期的な傾向把握」。週次レポートの SLI / EBR は SLO Status API で対象週・先週の7日間をそれぞれ取得する。SLO 定義の 30d は長期目標として区別し、バーンレートが1を超えた区間を例示すると、読み手のトレース調査を助ける。

</aside>

## 絶対に守ること

1. **エージェントが独自の閾値を持ち出して判定してはいけない。** 判定材料は monitor の発火とその波及だけ。閾値が必要だと判断したら、レポートに書くのではなく Datadog monitor を作る（`leaner-terraform` の `environments/datadog/`）。
2. **色（🔴🟡🟢⛔）は「読者への要求（対応要否）」にのみ使う。** monitor の発火状況には色を付けず、**件数と継続時間**で書く。
3. **`get_datadog_metric` は先週比トレンドの補足取得専用。** 閾値判定には使わない。
4. **対象ウインドウは直近のクローズ済み7日間。** 週クローズ前（partial-window）では累積系メトリクスを過少計上するため生成しない。
5. Datadog MCP の各呼び出しで `telemetry.intent`（英語・短く・PII なし）を必須指定。

## 構成 — 値はエージェント、形はスクリプト

**レポート本文を手で組まない。** エージェントが書くのは入力 JSON（値と所見）だけで、構成・固定文・節番号・§2 の有無・書式は `bin/weekly-report` が決める。テンプレートどおりに出ない揺らぎ（タイトル形式の崩れ・固定文の言い換え・台帳の行の統合・独自の節の追加）を、指示の強さではなく仕組みで止めるため。

| コマンド | やること |
| --- | --- |
| `bin/weekly-report window --product <p>` | 対象ウインドウ（JST・秒 / epoch ms）、ページタイトル、出力先 DB、重複確認クエリを JSON で出す |
| `bin/weekly-report stub --product <p>` | 入力 JSON の雛形を出す（テンプレートのスロットから生成するので常にテンプレートと一致） |
| `bin/weekly-report render <json>` | テンプレートと合成して完成形を作り、検証し、Notion 用の本文（`.notion.md`）を書き出す。問題があれば全件を列挙して失敗する |
| `bin/weekly-report validate <md>` | 完成形の Markdown を同じ基準で検証する（既存ページを手で直すとき） |

Claude Code では `.claude/settings.json` の hook（`bin/weekly-report guard`）が、レポート DB への書き込みを **render が検証した本文と一字一句同じもの**に制限する。手で組んだ本文は書き込めない。

テンプレートは**共通部分とプロダクト固有部分を合成して**作られる。

| ファイル | 役割 |
| --- | --- |
| このファイル | 全体の骨格と読み込み順 |
| `skills/weekly-infra-report/references/*.md` | 3プロダクト共通の手順 |
| `templates/report.md` | 共通レポートテンプレート（§1〜§3） |
| `templates/<lp\|pu\|fj>.md` | **プロダクト固有値**（変数表 ＋ 差し込みブロック） |

共通側には2種類の差し込み記法がある。どちらも `templates/<product>.md` から値を取る。

- `{{P.xxx}}` — 変数。プロダクト名・サービス名・ID などの単純置換。**表の値はそのまま差し込む literal**（URL やクエリ文字列の中に入るので、装飾やカッコ書きの注記を足さない）。
- `{{P:xxx}}` — ブロック。`templates/<product>.md` の `## {{P:xxx}}` 見出し配下をそのまま差し込む。

レポート本体（`templates/report.md`）の合成は `bin/weekly-report` がやる。この skill と `references/` に出てくる `{{P.xxx}}` は、読むときに `templates/<product>.md` の値に読み替える（`window` コマンドの出力にもタイトル・team タグ・出力先が入っている）。

## 読み込み順

**最初に `templates/<product>.md` を読む**（変数とブロックの供給元）。以降は必要になった時点で読む。**全部を先に読まない。**

| いつ | 読むもの | 目的 |
| --- | --- | --- |
| 開始時（必ず） | `templates/<product>.md` | 固定値・台帳・プロダクト固有注記（FJ なら `templates/fj.md`）を確認する |
| 手順1〜3 に入るとき | `references/collect.md` | monitor・イベント・SLO の収集方法を確認する |
| 手順5 に入るとき | `references/metrics.md` | 先週比トレンドの取得方法を確認する |
| **トリガ ON が確定したときだけ** | `references/investigate.md` ＋ `{{P:domain-notes}}` `{{P:playbook-notes}}` | 発火ウインドウの調査方法と固有の観点を確認する |
| 色を付けるとき | `references/evaluate.md` | 読者への対応要求の評価ルールを確認する |
| 入力 JSON を埋めるとき | `templates/report.md` の「ガイド:」＋ `references/output.md` | 各スロットに何をどう書くか（書式・該当なしの扱い・render が弾くもの）を確認する |
| メトリクスを取る前（必読） | `docs/datadog-mcp-tips.md` | 数値取得時の落とし穴を確認する |

読むときは複数ファイルを連結して一括出力したり、巨大な範囲を一度に `cat` したりしない。まず `grep -n` 等で見出しや対象ブロックの位置を把握し、次に `sed -n` 等でその目的に必要な範囲だけを読む。

MCP の出力上限で応答が退避・切り詰められた場合は、退避ファイルや部分プレビューを根拠に進めない。元ファイルをより小さい範囲に分けて再読し、必要なブロックを確認してから続行する。

トリガ OFF の週は `references/investigate.md` を**読まない**。これがこの分割の主な狙い。

## 全体の流れ

```
0. bin/weekly-report window で対象ウインドウとタイトルを確定   → 下記「ウインドウ」
1. 出力先 DB を作成日時 DESC で確認 → 同名ページがあれば中止 → 下記「重複防止」
2. bin/weekly-report stub で入力 JSON を作る                  → tmp/weekly-report/<product>.json
3. monitor 状態を一括取得（Observe の主軸）                    → collect.md 手順1
4. アラート発火イベントを収集（今週・先週）                     → collect.md 手順2
5. SLO の数値を取得                                          → collect.md 手順3
6. アプリ調査トリガを判定                                     → collect.md 手順4-a
   └ ON なら investigate.md を読んで発火ウインドウを深掘り
7. インフラ指標の週次値を取得（先週比トレンド用）                → metrics.md 手順5
8. 前週レポートを参照                                        → collect.md §0.5
   （3〜8 で得た値と所見は、その都度入力 JSON に書き込む）
9. bin/weekly-report render → 失敗したら JSON を直して再実行   → output.md
10. render が出した .notion.md をそのまま Notion に作成          → 下記「出力」
```

入力 JSON は次のように作り、以降はこのファイルを編集して値を埋めていく:

```bash
mkdir -p tmp/weekly-report
bin/weekly-report stub --product lp > tmp/weekly-report/lp.json
```

## ウインドウ

対象は **{{P.window_ja}}** の7日間（直近のクローズ済みの週）。

- 今週: `{{period_start}}`（{{P.window_start_ja}}）00:00 JST 〜 `{{period_end}}`（{{P.window_end_ja}}）23:59 JST
- 先週: その前の7日間

ウインドウとタイムスタンプは**自分で計算しない**。`bin/weekly-report window` が JST 基準で出す（UTC ずれや曜日の取り違えはウインドウ全体を壊す）:

```bash
bin/weekly-report window --product lp            # 直近のクローズ済みの週
bin/weekly-report window --product lp --end 2026-10-13   # 過去週を指定（終端曜日でない日・閉じていない週はエラー）
```

`window.from_s` / `to_s` は今週の Unix 秒、`prev_from_s` / `prev_to_s` は先週。調査リンクの `from_ts` / `to_ts` は **epoch ms**（`*_ms`）なので取り違えない。

## 重複防止（作成より先にやる）

出力先 DB（`{{P.output_db}}`）を作成日時の降順で確認し、対象ウインドウの同名ページが既にあれば**新規作成しない**。その場合は findings のみ報告して終わる。

クエリは `window` の出力の `duplicate_check_sql` をそのまま使い、結果のタイトルを `window` の出力の `title` と**完全一致**で比べる。

⚠️ タイトルプロパティ名はプロダクトで違う（`window` の出力の `title_prop`）。

## 出力ページタイトル（固定形式・変更禁止）

```
YYYY/MM/DD - MM/DD {{P.report_title}}
```

可変部は `YYYY/MM/DD - MM/DD` だけ。固定部はスペース・全角文字を含めて変更しない（重複防止の同名判定がタイトル一致に依存している）。**タイトルは自分で組み立てず、`window` / `render` の出力の `title` を一字一句そのまま使う。**

## 出力

1. 入力 JSON を埋め終えたら `bin/weekly-report render tmp/weekly-report/<product>.json` を実行する。
2. 失敗したら、列挙されたエラーを**入力 JSON 側で**すべて直して再実行する。出力された Markdown を手で直さない（直しても hook で書き込めない）。
3. 成功したら、出力 JSON の `notion_content`（`tmp/weekly-report/<product>-<YYYYMMDD>.notion.md`）の中身を**一字一句そのまま** `notion-create-pages` の `content` に、`title` を `title_prop` のプロパティに入れて、`data_source_id` を親にしてページを作成する。本文の先頭にタイトル行は付けない（タイトルはプロパティに入る）。
4. 作成後にページを取得し、タイトルが `title` と一致していることを確かめる。

render や Notion への書き込みが通らないときに、本文を手で組んで回避してはいけない。通らない理由をそのまま報告して止める。
