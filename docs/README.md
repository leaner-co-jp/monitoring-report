# docs

インフラモニタリング週次レポート運用の詳細知識。**必要なものだけ読む**（全部読む前提の構成にしていない）。

| ファイル | 内容 | 読むきっかけ |
| --- | --- | --- |
| [overview.md](overview.md) | 背景・課題・設計思想（monitor 駆動 / OODA）・運用サイクル・自動実行の仕組み | 全体像を把握したい |
| [workflow.md](workflow.md) | レポート生成の手順の俯瞰と、ファイル分割の地図 | 生成手順を直す／どのファイルに何があるか知りたい |
| [products.md](products.md) | LP / PU / FJ の固定値マトリクスとプロダクト固有の既知事項 | 固定値が必要／原因分析の前提を確認したい |
| [monitors.md](monitors.md) | monitor 一覧（ID・閾値）と評価ステータスのルール | monitor を参照・追加・変更する |
| [datadog-mcp-tips.md](datadog-mcp-tips.md) | Datadog MCP の落とし穴11件 | **メトリクスを取得する前に必読** |
| [report-style.md](report-style.md) | 出力ルール・日本語表現・Orient の書き方・リンク規約・章構成 | レポート本文を書く |
| [notion-sources.md](notion-sources.md) | Notion の URL 一覧・出力先 DB スキーマ・プロンプト節構成の地図 | Notion を読み書きする |
| [improvement-backlog.md](improvement-backlog.md) | ブラッシュアップ課題（**未解決の既知不整合を含む**） | 改善を検討する |
| [issues/](issues/) | 設計を固めた個別 issue（backlog から切り出したもの） | 特定の課題に着手する |
| [agent-builder/](agent-builder/) | Datadog Agent Builder 用の圧縮プロンプトと、20,000文字制限が実はバイト数チェックだった罠の記録 | Agent Builder に system prompt を貼る、文字数制限のエラーに遭遇した |
| [templates/](templates/) | レポート構成 v2 の**設計根拠**と、v1 からの移設記録（本体は [../templates/report.md](../templates/report.md)） | レポートの構成を見直す |

## 前提

**唯一の真実は3つ**: 手順 = [`skills/weekly-infra-report/`](../skills/weekly-infra-report/) / レポート構成 = [`../templates/report.md`](../templates/report.md) / プロダクト固有値 = [`../templates/<lp|pu|fj>.md`](../templates/)。ここはその写しではなく、運用知識・落とし穴・改善課題の置き場。食い違ったら上記を正とし、`docs/` を直す。

そのため `products.md` と `monitors.md` は性質上プロダクト固有値ファイルと重複するが、**3プロダクトを並べて差分を見る**ためのもので、1プロダクト1ファイルの側にはこの横断ビューがない。

Notion は**出力先**（生成したレポートページを作る先）としてのみ登場する。ページ URL と DB スキーマは [notion-sources.md](notion-sources.md)。
