# infra-monitoring-report

リーナーテクノロジーズの各プロダクトチームが週次で開催する**インフラモニタリング会（モニ会）**用のレポートを、AI エージェントが Datadog から生成して Notion に出力するプロジェクト。

対象プロダクトは3つ。**LP** = リーナー見積 / **PU** = リーナー購買 / **FJ** = リーナーコネクト。

## 最重要の前提

- **レポート生成は3つの層の合成**（2026-09-15 に単一ファイル方式から分割）。**Notion は出力先**であって、指示の置き場ではない。
  - **手順（3プロダクト共通）** = `skills/weekly-infra-report/`（agent 非依存の skill。`SKILL.md` ＋ `references/` 5本）
  - **レポート構成（共通）** = `templates/report.md`
  - **プロダクト固有値** = `templates/<lp|pu|fj>.md`（変数表 `{{P.xxx}}` ＋ 差し込みブロック `{{P:xxx}}`）
- **固有値の唯一の真実は `templates/<product>.md`、手順の唯一の真実は skill 側。** 数値や固定値が食い違ったらこれらを正とし、`docs/` を直す。
- `docs/` は `templates/` の写しではなく、**運用知識・落とし穴・改善課題の置き場**。テンプレートを直したら、関連する `docs/` の記述も同じコミットで追従させる。
- 生成方式は **monitor 駆動の OODA**。閾値判定とスパイク検知は Datadog monitor に委譲し、エージェントは monitor 状態とアラート発火を「シグナル」として集め、Observe / Orient を厚く書く。Decide / Act は**候補提示までに留める**（決めるのは人間）。
- monitor 駆動の目的は**人間とエージェントの間で緊急度の認識を一致させること**。**エージェントが独自の閾値を持ち出して判定してはいけない**（モデルごとに判定がぶれ、週をまたいだ比較が成立しなくなる）。経緯は [docs/overview.md](docs/overview.md)。
- `get_datadog_metric` は**先週比トレンドの補足取得専用**。閾値判定には使わない。
- 実行はスケジュールタスク（cron）で自動化済み。LP は水曜 09:00 JST、PU・FJ は金曜 09:05 JST。詳細は [docs/overview.md](docs/overview.md)。

## 絶対に守るルール

1. **対象ウインドウ**: LP = 水曜〜火曜 / PU・FJ = 金曜〜木曜。いずれも**直近のクローズ済みの7日間**。週クローズ前（partial-window）だと累積系メトリクスを過少計上するので生成しない。
2. **重複防止**: 作成前に出力先 DB を作成日時 DESC で確認し、対象ウインドウの同名ページが既にあれば**新規作成しない**（findings のみ報告）。
3. **FJ の team タグは `connect`**。`fj` では0件になる。
4. **ページタイトルは固定形式**。可変部は `YYYY/MM/DD - MM/DD` だけ。
5. `templates/report.md` 冒頭の「運用ガイド」トグルはレポートに含めない。**出力に `{{P.` / `{{P:` が残っていたら合成ミス**（書き込み前に確認）。
6. 旧方式のローカル `*-weekly-report-template.md`、旧 AI-Agent ページ、**Notion 側の旧プロンプト＆テンプレートページ**は stale。参照しない。
7. Datadog MCP の各呼び出しで `telemetry.intent`（英語・短く・PII なし）を必須指定。
8. **色（🔴🟡🟢⛔）は「読者への要求（対応要否）」にのみ使う。monitor の発火状況には色を付けない** — 発火は判定ではなく事実なので、件数と継続時間で書く。判定の当て方は [docs/monitors.md](docs/monitors.md)。

## リポジトリの構成

| パス | 中身 |
| --- | --- |
| `skills/weekly-infra-report/SKILL.md` | **生成手順のエントリ**。骨格・読み込み順・ウインドウ・重複防止 |
| `skills/weekly-infra-report/references/` | 共通手順。`collect` 手順1-3 / `investigate` 手順4（**トリガ ON の週だけ読む**）/ `metrics` 手順5 / `evaluate` 評価ルール / `output` 出力・検証 |
| `templates/report.md` | 共通レポートテンプレート（§1〜§3） |
| `templates/lp.md` / `pu.md` / `fj.md` | **プロダクト固有値のみ**（完成形テンプレートではない） |
| `docs/` | 運用知識・落とし穴・改善課題。上記の背景を補うもの |

レポート生成は「LP の週次レポートを生成して」等で `skills/weekly-infra-report/` を起点にする。Codex を含む各エージェントは、対応する skill の自動検出がない環境ではこのパスを明示して読む。トリガ OFF（monitor 発火なし）の週は `references/investigate.md` を読まないのが分割の主な狙い。

## docs/ の読み方

必要なときに必要なものだけ読む。全部読む必要はない。

| ファイル | いつ読むか |
| --- | --- |
| [docs/overview.md](docs/overview.md) | プロジェクトの全体像・運用サイクル・自動実行の仕組みを知りたいとき |
| [docs/workflow.md](docs/workflow.md) | レポートを生成する／生成手順を直すとき |
| [docs/products.md](docs/products.md) | プロダクト固有の固定値（SLO ID・ECS サービス名・RDS・ダッシュボード）が必要なとき |
| [docs/monitors.md](docs/monitors.md) | monitor 一覧・ID・閾値を参照するとき、monitor を追加・変更するとき |
| [docs/datadog-mcp-tips.md](docs/datadog-mcp-tips.md) | Datadog MCP でメトリクスを取るとき（**取得前に必読**。数値を誤らせる罠が集約されている） |
| [docs/report-style.md](docs/report-style.md) | レポート本文を書くとき（日本語表現・単位・リンク規約） |
| [docs/notion-sources.md](docs/notion-sources.md) | 出力先 Notion DB の URL・スキーマ・重複防止クエリが必要なとき |
| [docs/improvement-backlog.md](docs/improvement-backlog.md) | ブラッシュアップを検討するとき。**未解決の既知不整合もここにある** |

## レポート構成の現状（プロダクトで違う）

- **3プロダクトとも v2**（LP: 2026-08-21 / PU: 2026-08-26 / FJ: 2026-08-27 に確定。2026-09-15 に Notion から移設し、同日 skill ＋ 共通テンプレート ＋ プロダクト固有値に分割）。**3セクション** = §1 総合評価（必読・常に存在）/ §2 調査（**monitor 発火があった週のみ存在**・インシデント単位）/ §3 付録（台帳。数値の唯一の住所）。設計根拠は [docs/templates/lp-template-revised.md](docs/templates/lp-template-revised.md)、v1 からの移設記録は [docs/templates/lp-template-v1-migration.md](docs/templates/lp-template-v1-migration.md)。PU・FJ への横展開差分もこれらのファイルの追記を参照。
- 旧 v1（5セクション・レイヤ別網羅）は全プロダクトで廃止済み。過去のレポートページの構成を参照するときのみ、旧版であることに注意する。

## 現在の未解決事項（詳細は improvement-backlog.md）

- **スケジュールタスクの SKILL.md がまだ Notion のプロンプト＆テンプレートページを参照している**（`~/.claude/scheduled-tasks/`）。`skills/weekly-infra-report/` を使う形への差し替えが未了（backlog M）。
- LP のスケジュールタスクにだけ「レポートの日本語表現」の指示が入っていない。
- **monitor の無い独自閾値が2件あった**（v2 で落とした。テンプレートに戻すのではなく monitor を作るのが正しい対処）: SLO の `EBR < 20%` と、Worker-Long の `max% で週4回以上のスパイク / 70% 超え`。いずれもダッシュボードのノートやテンプレートの Orient に書かれていただけで Datadog monitor の裏付けがない。
- **Worker 系 ECS CPU monitor（3プロダクト共通）が瞬間値検知で校正不良**。仕様どおりの稼働が critical として発火している（backlog L）。対処は monitor の校正であって毎週の再説明ではない。
