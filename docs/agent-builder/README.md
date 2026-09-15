# Datadog Agent Builder 用の圧縮プロンプト

Datadog Agent Builder の system prompt には `Generic Error: system prompt cannot be more than 20000 characters` という制限がある。**この「20000 characters」は実際には UTF-8 バイト数のチェックであり、Unicode 文字数ではない。**

## 罠: 文字数とバイト数の食い違い

日本語（ひらがな・カタカナ・大半の漢字）は UTF-8 で **1文字 = 3バイト**。ASCII（英数字・記号・クエリ文字列・ID）は 1文字 = 1バイト。日本語と ASCII が混在するドキュメントは、見た目の文字数よりバイト数がかなり大きくなる。

LP のインフラ週次レポートプロンプト（当時は Notion 上。現 [`templates/lp.md`](../../templates/lp.md)）で実測した数値:

| | Unicode 文字数 | UTF-8 バイト数 |
| --- | --- | --- |
| 元の文章（移設前の Notion ページ） | 17,229 | **30,805**（❌ Agent Builder の制限超過） |
| 圧縮版（[lp-prompt-compact.md](lp-prompt-compact.md)） | 10,899 | **19,485**（✅ 残り515バイト） |

`wc -m` はシェルの locale が `C`（非UTF-8）だとバイト数にフォールバックする罠があるため使わない。**正確に測るには必ず Python で UTF-8 エンコードしたバイト長を見る**:

```bash
python3 -c "print(len(open('FILE', encoding='utf-8').read().encode('utf-8')))"
```

## このディレクトリのファイル

| ファイル | 内容 |
| --- | --- |
| [lp-prompt-compact.md](lp-prompt-compact.md) | LP（リーナー見積）インフラ週次レポートプロンプトの圧縮版。19,485バイト。元の実行指示（現 [`templates/lp.md`](../../templates/lp.md)）の全ての判定ロジック・クエリ・閾値・落とし穴の警告（scalar dedup / vCPU 正規化 / rollup / apm-traces の storage=hot クランプ / aggregate_spans の 0 buckets）を保持したまま、冗長な説明文と一部の重複記述だけを削って圧縮したもの。**テンプレート改訂案 v2（3セクション構成）に同期済み** |

## バイト数が足りなくなったときの削り方

v2 同期のときに 22,562 バイトまで膨らんで 2,500 バイト以上削る必要が出た。そのとき有効だった順に:

1. **テンプレートと重複した記述を消す**（最も効果的かつ設計上も正しい）。構成の規則はテンプレート側の運用ガイドが持つので、プロンプト側は短いポインタで足りる。「§0.7 出力構成」と「台帳の校正メモの記法」がこれで約950バイト縮んだ。プロジェクトの原則（構成の定義はテンプレート、取得と評価の定義はプロンプト）に沿うので、単なる短縮ではなく責務分離の改善になる。
2. **同じことの3回目の記述を消す**。色の付け方のルールが §0.4 / §0.6 / 手順5 の3箇所にあった。canonical な1箇所（§0.6）を残す。
3. **箇条書きを1段落に畳む**。判定ロジックを削らずに済む。
4. **散文の冗長表現を削る**。

**削ってはいけないもの**: クエリ文字列・閾値の数値・固定値（SLO ID / ECS サービス名）・落とし穴の警告・§0.8（日本語表現の指示。[backlog B](../improvement-backlog.md) への対応そのもの）。

## PU・FJ で同じ対応が必要になったら

PU・FJ のプロンプトも LP とほぼ同じ構成・ボリュームなので、Agent Builder に載せる場合は同じ理由で同じエラーが出る見込み。対応するときの手順:

1. [`templates/pu.md`](../../templates/pu.md) / [`templates/fj.md`](../../templates/fj.md) の §0（実行指示）部分を取り出す
2. 上記の Python ワンライナーで実際の UTF-8 バイト数を測る（`wc -m` は使わない）
3. 20,000 バイトを超えていたら、判定ロジック・クエリ文字列・閾値・落とし穴の警告は**削らず**、冗長な説明文・重複した rationale・チーム名の全角表記の重複などを削って圧縮する
4. 圧縮後も Python で実際のバイト数を確認し、500バイト程度の安全マージンを確保する
5. `docs/agent-builder/<team>-prompt-compact.md` として保存する

## 注意

この圧縮版は Agent Builder に貼るための派生物であり、**唯一の真実は [`templates/<product>.md`](../../templates/)**（[AGENTS.md](../../AGENTS.md) の最重要の前提を参照）。`templates/` が更新されたら、この圧縮版も再生成して追従させる。放置すると本体と圧縮版が食い違う stale drift になる。
