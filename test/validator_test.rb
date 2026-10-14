# frozen_string_literal: true

require_relative "test_helper"

# レンダラを経由しない（手で直された）Markdown を想定して、壊し方ごとに検出できるかを見る。
class ValidatorTest < Minitest::Test
  include TestHelper

  def valid_markdown(code = "lp")
    render(code, quiet_week(code))
  end

  def errors_for(markdown)
    WeeklyReport::Validator.new(markdown).run.errors
  end

  def assert_detects(markdown, fragment)
    errors = errors_for(markdown)
    assert(errors.any? { |e| e.include?(fragment) }, "#{fragment.inspect} を含むエラーがない: #{errors.inspect}")
  end

  def test_rendered_markdown_is_valid
    WeeklyReport::Product::CODES.each do |code|
      assert_empty errors_for(valid_markdown(code)), code
      assert_empty errors_for(render(code, firing_week(code))), code
    end
  end

  def test_drifted_title
    markdown = valid_markdown.sub(/\A# .*\n/, "# リーナー見積インフラモニタリング 週次レポート 2026/10/07〜10/13\n")
    assert_detects markdown, "タイトルが固定形式"
  end

  def test_extra_section
    markdown = valid_markdown + "\n## 4. 収集記録\n\n- 独自の節\n"
    assert_detects markdown, "テンプレートにない見出し: ## 4. 収集記録"
  end

  def test_missing_section
    markdown = valid_markdown.sub(/^### 評価ルール\n.*?(?=^### 総合ステータス)/m, "")
    assert_detects markdown, "欠落: ### 評価ルール"
  end

  def test_reworded_fixed_text
    markdown = valid_markdown.sub("| 🟡 | 次週も再発したら判断 | 覚えておいて次週の同項目を見る |", "| 🟡 | 継続観察が必要 | 次週以降の変化を確認する |")
    assert_detects markdown, "固定行が欠落・改変"
  end

  def test_merged_ledger_rows
    markdown = valid_markdown.sub(/^\| アプリ \| Rails p50（週平均）.*\n/, "")
    assert_detects markdown, "指標の行がテンプレートと一致しない"
  end

  def test_color_in_firing_column
    markdown = valid_markdown.sub(/(\| API CPU max \/ avg（8 GiB） \|[^\n]*?\| )発火なし( \|)/, '\1🔴 critical 1回 / 10分\2')
    assert_detects markdown, "monitor発火の列に色が付いている"
  end

  def test_firing_format
    markdown = valid_markdown.sub(/(\| API CPU max \/ avg（8 GiB） \|[^\n]*?\| )発火なし( \|)/, '\1warning 6回（各10分）\2')
    assert_detects markdown, "monitor発火の書式が違う"
  end

  def test_yellow_overall_status
    markdown = valid_markdown.sub("**総合ステータス**: 🟢 ", "**総合ステータス**: 🟡 ")
    assert_detects markdown, "総合ステータスの色は 🟢 か 🔴"
  end

  def test_unavailable_without_reason
    markdown = valid_markdown.sub("- 特記事項なし", "- ⚠️ 取得不可")
    assert_detects markdown, "「: <理由>」がない"
  end

  def test_bare_monitor_id
    markdown = valid_markdown.sub("- 特記事項なし", "- API CPU monitor #297262484 が発火")
    assert_detects markdown, "monitor ID #297262484 がリンクなし"
  end

  def test_monitor_link_without_id
    markdown = valid_markdown.sub("- 特記事項なし", "- [API CPU](https://app.datadoghq.com/monitors/297262484) が発火")
    assert_detects markdown, "monitor 297262484 のリンクの直後に"
  end

  def test_leftover_guide_and_placeholder
    markdown = valid_markdown.sub("- 特記事項なし", "- ガイド: {{R.notes[]}}")
    assert_detects markdown, "プレースホルダ"
    assert_detects markdown, "記入ガイド"
  end

  def test_trigger_on_without_investigation
    markdown = valid_markdown.sub("**アプリ調査トリガ**: OFF", "**アプリ調査トリガ**: ON")
    assert_detects markdown, "アプリ調査トリガが ON なのに §2 調査がない"
  end

  def test_incident_label_must_match_color
    markdown = render("lp", firing_week("lp")).sub("（対応要否 🔴 今週判断", "（対応要否 🔴 記録のみ")
    assert_detects markdown, "対応要否が色と合わない"
  end
end
