# frozen_string_literal: true

require_relative "test_helper"
require "open3"

class CLITest < Minitest::Test
  include TestHelper

  BIN = File.join(WeeklyReport.root, "bin", "weekly-report")

  def setup
    @approval_dir = Dir.mktmpdir
  end

  def teardown
    FileUtils.rm_rf(@approval_dir)
  end

  def run_cli(*args, stdin: "")
    Open3.capture3({ "WEEKLY_REPORT_APPROVAL_DIR" => @approval_dir }, "ruby", BIN, *args, stdin_data: stdin)
  end

  def test_window_outputs_title_and_epoch
    out, _err, status = run_cli("window", "--product", "fj", "--today", "2026-10-16")
    assert status.success?
    info = JSON.parse(out)
    assert_equal "2026/10/09 - 10/15 リーナーコネクトインフラモニタリング 週次レポート", info["title"]
    assert_equal "team:connect", info["team_tag"]
    assert_equal "2026-10-15", info["window"]["end"]
  end

  def test_render_writes_files_and_validate_accepts_them
    Dir.mktmpdir do |dir|
      input = File.join(dir, "lp.json")
      File.write(input, JSON.generate(quiet_week("lp")))
      out, err, status = run_cli("render", input, "--out-dir", dir, "--today", "2026-10-14")
      assert status.success?, err
      result = JSON.parse(out)
      assert_equal window("lp").title, result["title"]
      assert File.exist?(result["notion_content"])

      out, err, status = run_cli("validate", result["markdown"])
      assert status.success?, err
      assert_match(/\AOK: /, out)
      assert_equal 1, Dir[File.join(@approval_dir, "*.json")].size
    end
  end

  def test_render_reports_errors
    Dir.mktmpdir do |dir|
      data = quiet_week("lp")
      data["status"]["color"] = "🟡"
      input = File.join(dir, "lp.json")
      File.write(input, JSON.generate(data))
      _out, err, status = run_cli("render", input, "--out-dir", dir, "--today", "2026-10-14")
      refute status.success?
      assert_match(/総合ステータスの色は 🟢 か 🔴/, err)
      refute File.exist?(File.join(dir, "lp-20261013.notion.md"))
    end
  end

  def test_guard_exits_2_when_blocking
    event = {
      "tool_name" => "mcp__claude_ai_Notion__notion-create-pages",
      "tool_input" => {
        "parent" => { "data_source_id" => "353daeae-0b01-8043-bd60-000b0cef4826" },
        "pages" => [{ "properties" => {}, "content" => "手組みの本文" }]
      }
    }
    _out, err, status = run_cli("guard", stdin: JSON.generate(event))
    assert_equal 2, status.exitstatus
    assert_match(/書き込みを止めた/, err)
  end
end
