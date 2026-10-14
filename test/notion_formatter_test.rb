# frozen_string_literal: true

require_relative "test_helper"

class NotionFormatterTest < Minitest::Test
  include TestHelper

  def convert(markdown)
    WeeklyReport::NotionFormatter.convert(markdown)
  end

  def test_drops_title_line
    assert_equal "本文\n", convert("# タイトル\n\n本文\n")
  end

  def test_converts_pipe_table
    markdown = <<~MD
      | 指標 | 今週 |
      | --- | --- |
      | GET /a\\|b | 1ms |
    MD
    expected = <<~MD
      <table header-row="true">
      \t<tr>
      \t\t<td>指標</td>
      \t\t<td>今週</td>
      \t</tr>
      \t<tr>
      \t\t<td>GET /a|b</td>
      \t\t<td>1ms</td>
      \t</tr>
      </table>
    MD
    assert_equal expected, convert(markdown)
  end

  def test_converts_aside_to_callout
    markdown = <<~MD
      <aside>
      ⚠️

      - 注記1
          - 入れ子
      </aside>
    MD
    assert_equal %(<callout icon="⚠️">\n\t- 注記1\n\t\t- 入れ子\n</callout>\n), convert(markdown)
  end

  def test_indentation_and_lone_quote_marker
    markdown = "> 引用\n>\n\n- 親\n    - 子\n"
    assert_equal "> 引用\n\n- 親\n\t- 子\n", convert(markdown)
  end

  def test_rendered_report_has_no_pipe_tables_or_asides
    notion = convert(render("fj", firing_week("fj")))
    refute_match(/^\|/, notion)
    refute_includes notion, "<aside>"
    refute_match(/^ {4}/, notion)
    assert_includes notion, %(<callout icon="📌">)
  end
end
