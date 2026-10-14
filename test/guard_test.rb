# frozen_string_literal: true

require_relative "test_helper"

class GuardTest < Minitest::Test
  include TestHelper

  # 承認記録は root/tmp に書かれるので、テンプレートだけ本物を見せる一時 root を使う
  def setup
    @root = Dir.mktmpdir
    FileUtils.cp_r(File.join(WeeklyReport.root, "templates"), @root)
    @content = WeeklyReport::NotionFormatter.convert(render("lp", quiet_week("lp"), root: @root))
    WeeklyReport::Approval.approve!(@root, content: @content, title: window("lp").title, product: product("lp"))
  end

  def teardown
    FileUtils.rm_rf(@root)
  end

  def guard
    WeeklyReport::Guard.new(root: @root)
  end

  def create_event(content:, title: window("lp").title, parent: { "data_source_id" => "353daeae-0b01-8043-bd60-000b0cef4826" })
    {
      "tool_name" => "mcp__claude_ai_Notion__notion-create-pages",
      "tool_input" => {
        "parent" => parent,
        "pages" => [{ "properties" => { "ドキュメント名" => title }, "content" => content }]
      }
    }
  end

  def test_allows_approved_content
    assert_nil guard.check(create_event(content: @content))
  end

  def test_ignores_blank_line_and_trailing_space_differences
    assert_nil guard.check(create_event(content: @content.gsub("\n", "\n\n").gsub(/$/, "  ")))
  end

  def test_blocks_hand_written_content
    reason = guard.check(create_event(content: @content.sub("- 特記事項なし", "- 手で足した行")))
    assert_match(/書き込みを止めた/, reason)
    assert_includes reason, %(承認済み: "- 特記事項なし")
    assert_includes reason, %(渡した本文: "- 手で足した行")
  end

  def test_blocks_wrong_title
    reason = guard.check(create_event(content: @content, title: "リーナー見積インフラモニタリング 週次レポート 2026/10/07〜10/13"))
    assert_match(/承認済みのタイトルと違う/, reason)
  end

  def test_database_id_parent_is_also_guarded
    reason = guard.check(create_event(content: "手組み", parent: { "database_id" => "353daeae0b0180528fa0c6c212b74441" }))
    refute_nil reason
  end

  def test_other_databases_are_not_guarded
    assert_nil guard.check(create_event(content: "無関係なページ", parent: { "data_source_id" => "ffffffff-0000-0000-0000-000000000000" }))
  end

  def test_full_replace_of_report_page_is_guarded
    event = {
      "tool_name" => "mcp__claude_ai_Notion__notion-update-page",
      "tool_input" => { "command" => "replace_content", "new_str" => "本レポートの全体報告はここで終了です。 手組み" }
    }
    refute_nil guard.check(event)

    event["tool_input"]["new_str"] = @content
    assert_nil guard.check(event)
  end

  def test_other_tools_pass
    assert_nil guard.check("tool_name" => "mcp__claude_ai_Notion__notion-fetch", "tool_input" => {})
  end
end
