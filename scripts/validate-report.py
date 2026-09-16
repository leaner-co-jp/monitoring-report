#!/usr/bin/env python3
"""合成した週次レポート（完成成果物）を Notion へ書き込む前に検査する。

使い方:
    python3 scripts/validate-report.py <report.md> --product lp [--fired|--no-fired]

依存なし（標準ライブラリのみ）。検査に落ちたら終了コード 1 を返す。
期待するタイトルは templates/<product>.md の変数表から読むので、
固定値の正本はテンプレート側のままである。
"""

from __future__ import annotations

import argparse
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent

REQUIRED_HEADINGS = [
    "## 🔗 調査リンク",
    "## 1. 🎯 総合評価",
    "### 色の意味（レポート全体で共通 / 固定文。そのまま出力する）",
    "### 評価ルール（レポート全体で共通 / 固定文。そのまま出力する）",
    "### 総合ステータス",
    "### 今週のシグナル変化（先週比）",
    "### 先週比の主要変化",
    "### Decide / Act 候補（人間判断用）",
    "### 報告の結び",
    "## 3. 📎 付録（記録用）",
    "### 前回 Decide / Act の反映状況",
    "### 3.1 全指標の週次記録（台帳）",
    "### 3.2 取得時刻・期間",
    "### 3.3 今週の取得上の注記",
]

INVESTIGATION_HEADING = "## 2. 🔍 調査"

# 「色の意味」「評価ルール」は固定文なので、落ちていないかを本文で直接見る
FIXED_BLOCKS = [
    ("色の意味の表", r"\|\s*🔴\s*\|.*今週中に人の判断が必要"),
    ("評価ルール 規則1", r"^1\.\s.*発火中.*monitor", re.M),
    ("評価ルール 規則4", r"^4\.\s.*いずれも該当しない", re.M),
]


def load_report_title(product: str) -> str | None:
    """templates/<product>.md の変数表から report_title を読む。"""
    path = ROOT / "templates" / f"{product}.md"
    if not path.exists():
        return None
    m = re.search(r"^\|\s*`\{\{P\.report_title\}\}`\s*\|\s*(.+?)\s*\|$",
                  path.read_text(encoding="utf-8"), re.M)
    return m.group(1) if m else None


def check(text: str, product: str, fired: bool | None) -> list[str]:
    errors: list[str] = []

    # --- タイトル形式 ---
    first = next((l for l in text.splitlines() if l.startswith("# ")), None)
    expected = load_report_title(product)
    if first is None:
        errors.append("タイトル行（`# …`）が無い")
    else:
        title = first[2:].strip()
        if not re.match(r"^\d{4}/\d{2}/\d{2} - \d{2}/\d{2} ", title):
            errors.append(f"タイトルが `YYYY/MM/DD - MM/DD …` の形式でない: {title}")
        elif expected and not title.endswith(expected):
            errors.append(f"タイトルの固定部が一致しない。期待: …{expected} / 実際: {title}")

    # --- 必須見出し ---
    for h in REQUIRED_HEADINGS:
        if h not in text:
            errors.append(f"必須見出しが無い: {h}")

    # --- §2 と発火有無の整合 ---
    has_sec2 = INVESTIGATION_HEADING in text
    if fired is True and not has_sec2:
        errors.append("monitor 発火ありなのに `## 2. 🔍 調査` が無い")
    if fired is False and has_sec2:
        errors.append("monitor 発火なしなのに `## 2. 🔍 調査` がある（見出しごと省く）")

    # --- 未置換プレースホルダ ---
    for pat, label in ((r"\{\{P\.", "変数 `{{P.`"), (r"\{\{P:", "ブロック `{{P:`")):
        n = len(re.findall(pat, text))
        if n:
            errors.append(f"未置換の{label} が {n} 箇所残っている")
    generic = [m.group(0) for m in re.finditer(r"\{\{[^{}]{1,80}\}\}", text)
               if not m.group(0).startswith(("{{P.", "{{P:"))]
    if generic:
        sample = ", ".join(sorted(set(generic))[:5])
        errors.append(f"未置換のプレースホルダが {len(generic)} 箇所残っている（例: {sample}）")

    # --- 記入ガイドの出力残存 ---
    guides = [l.strip() for l in text.splitlines() if re.match(r"^\s*-?\s*ガイド[:：]", l)]
    if guides:
        errors.append(f"「ガイド:」で始まる記入指示が {len(guides)} 行残っている（例: {guides[0][:40]}）")
    if "テンプレート運用ガイド" in text:
        errors.append("テンプレート冒頭の運用ガイドが出力に残っている")

    # --- 固定ブロック ---
    for name, pat, *flags in FIXED_BLOCKS:
        if not re.search(pat, text, *flags):
            errors.append(f"固定ブロックが欠けている: {name}")

    # --- 台帳の校正メモ ---
    errors.extend(check_ledger(text))

    # --- 取得不可に理由があるか ---
    for m in re.finditer(r"⚠️\s*取得不可\s*[:：]?\s*(.*)", text):
        if not m.group(1).strip().strip("`"):
            errors.append("`⚠️ 取得不可` に理由が書かれていない箇所がある")
            break

    return errors


def check_ledger(text: str) -> list[str]:
    """§3.1 台帳の各データ行で、最終列（校正メモ）が埋まっているかを見る。"""
    lines = text.splitlines()
    try:
        start = next(i for i, l in enumerate(lines) if l.startswith("### 3.1 "))
        end = next(i for i, l in enumerate(lines[start + 1:], start + 1)
                   if l.startswith("### "))
    except StopIteration:
        return []
    rows = [l for l in lines[start:end] if l.strip().startswith("|")]
    data = [r for r in rows if not re.match(r"^\|[\s:|-]+\|$", r.strip())][1:]  # ヘッダと区切りを除く
    blank = 0
    for r in data:
        cells = [c.strip() for c in r.strip().strip("|").split("|")]
        if len(cells) >= 7 and not cells[-1]:
            blank += 1
    if blank:
        return [f"§3.1 台帳の「校正メモ」列が空の行が {blank} 行ある（毎行埋める）"]
    return []


def main() -> int:
    ap = argparse.ArgumentParser(description="週次レポートの完成成果物を検査する")
    ap.add_argument("report", help="合成済みレポートの Markdown ファイル")
    ap.add_argument("--product", required=True, choices=["lp", "pu", "fj"])
    g = ap.add_mutually_exclusive_group()
    g.add_argument("--fired", dest="fired", action="store_true",
                   help="今週 monitor の発火があった（§2 が必要）")
    g.add_argument("--no-fired", dest="fired", action="store_false",
                   help="今週 monitor の発火が無かった（§2 は出さない）")
    ap.set_defaults(fired=None)
    args = ap.parse_args()

    path = pathlib.Path(args.report)
    if not path.exists():
        print(f"✗ ファイルが無い: {path}", file=sys.stderr)
        return 2

    errors = check(path.read_text(encoding="utf-8"), args.product, args.fired)

    if args.fired is None:
        print("… --fired / --no-fired が未指定のため、§2 の整合は検査していない")
    if errors:
        print(f"✗ {len(errors)} 件の問題が見つかった。Notion へ書き込む前に直す。\n")
        for e in errors:
            print(f"  - {e}")
        return 1
    print("✓ 検査を通過した")
    return 0


if __name__ == "__main__":
    sys.exit(main())
