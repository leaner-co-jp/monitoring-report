# frozen_string_literal: true

require_relative "test_helper"

class RendererTest < Minitest::Test
  include TestHelper

  # テンプレートから作ったスタブを埋めれば、3プロダクトとも検証まで通る（テンプレートとレンダラの整合）
  def test_stub_round_trip_for_every_product
    WeeklyReport::Product::CODES.each do |code|
      markdown = render(code, quiet_week(code))
      assert markdown.start_with?("# #{window(code).title}\n"), code
      refute_match(/\{\{|\}\}/, markdown, code)
    end
  end

  def test_quiet_week_has_no_investigation_section
    markdown = render("lp", quiet_week("lp"))
    refute_includes markdown, "## 2. "
    refute_includes markdown, "§2 調査を"
    assert_includes markdown, "§3 付録を参照してください。"
    assert_includes markdown, "- 初回扱い（前週レポート未検出）"
    assert_includes markdown, "- 特記事項なし"
  end

  def test_empty_lists_become_none
    markdown = render("lp", quiet_week("lp"))
    assert_includes markdown, "- **critical**:\n    - 該当なし\n"
    assert_includes markdown, "- 🔴 **緊急（今週中に決める）**:\n    - 該当なし\n"
  end

  def test_list_items_become_bullets
    data = quiet_week("lp")
    data["signals"]["warning"] = ["warning その1", "warning その2"]
    markdown = render("lp", data)
    assert_includes markdown, "- **warning**:\n    - warning その1\n    - warning その2\n"
  end

  def test_firing_week_renders_numbered_incidents
    data = firing_week("pu")
    data["incidents"] << incident("🟡").merge("title" => "2件目")
    markdown = render("pu", data)
    assert_includes markdown, "### 2.1 API メモリの高騰（対応要否 🔴 今週判断 / critical 1回 / 10分）"
    assert_includes markdown, "### 2.2 2件目（対応要否 🟡 次週判断 / critical 1回 / 10分）"
    assert_includes markdown, "§2 調査を"
    assert_equal 1, markdown.scan("**調査時の前提**").size
  end

  def test_apm_table_only_when_rows_exist
    data = firing_week("lp")
    refute_includes render("lp", data), "| 区分 | resource_name |"

    data["incidents"][0]["apm"] = [
      { "category" => "劣化", "resource" => "GET /a|b", "baseline_p50" => "10ms", "window_p50" => "30ms", "change" => "+200%" }
    ]
    markdown = render("lp", data)
    assert_includes markdown, "| 劣化 | GET /a\\|b | 10ms | 30ms | +200% |"
  end

  def test_metrics_fill_both_tables_by_label
    data = quiet_week("lp")
    data["metrics"]["Rails p95（週平均）"].merge!("this" => "61.25ms", "prev" => "57.69ms", "change" => "+6.2%", "orient" => "軽微な上昇")
    markdown = render("lp", data)
    assert_includes markdown, "| Rails p95（週平均） | 61.25ms | 57.69ms | +6.2% | 軽微な上昇 |"
    assert_includes markdown, "| アプリ | Rails p95（週平均） | 61.25ms | 57.69ms | +6.2% | — | memo の値 |"
  end

  def test_reports_all_missing_values_at_once
    data = quiet_week("lp")
    data["status"].delete("summary")
    data["metrics"].delete("RDS Writer CPU max")
    data["metrics"]["Rails p50（週平均）"]["this"] = ""
    errors = render_errors("lp", data)
    assert(errors.any? { |e| e.include?("status.summary がない") })
    assert(errors.any? { |e| e.include?('metrics["RDS Writer CPU max"] がない') })
    assert(errors.any? { |e| e.include?('metrics["Rails p50（週平均）"].this が空') })
  end

  def test_rejects_unknown_keys
    data = quiet_week("lp")
    data["status"]["sumary"] = "typo"
    data["metrics"]["存在しない指標"] = { "this" => "1" }
    data["incidents"] = []
    errors = render_errors("lp", data)
    assert(errors.any? { |e| e.include?("status.sumary はテンプレートにないキー") })
    assert(errors.any? { |e| e.include?('metrics["存在しない指標"] はどの表にもない指標') })
  end

  def test_rejects_overwriting_fixed_cells
    data = quiet_week("lp")
    data["metrics"]["Writer Free Memory (avg)"]["fired"] = "発火なし"
    errors = render_errors("lp", data)
    assert(errors.any? { |e| e.include?("固定値") })
  end

  def test_firing_in_ledger_requires_investigation
    data = quiet_week("fj")
    data["metrics"]["API メモリ max% / avg%"]["fired"] = "critical 1回 / 10分"
    errors = render_errors("fj", data)
    assert(errors.any? { |e| e.include?("§2 調査がない") })
  end

  def test_max_rule
    data = firing_week("lp")
    data["status"]["color"] = "🟢"
    errors = render_errors("lp", data)
    assert(errors.any? { |e| e.include?("max ルール") })

    data = firing_week("lp", color: "🟡")
    data["status"]["color"] = "🔴"
    errors = render_errors("lp", data)
    assert(errors.any? { |e| e.include?("max ルール") })
  end

  def test_rejects_invalid_incident_color
    data = firing_week("lp")
    data["incidents"][0]["color"] = "🟠"
    errors = render_errors("lp", data)
    assert(errors.any? { |e| e.include?("incidents[0].color") })
  end

  def test_rejects_newline_in_list_item
    data = quiet_week("lp")
    data["notes"] = ["1行目\n2行目"]
    errors = render_errors("lp", data)
    assert(errors.any? { |e| e.include?("notes[0] に改行がある") })
  end

  def test_load_input_checks_window
    data = quiet_week("lp")
    product, window = WeeklyReport::Renderer.load_input(data, today: TODAY)
    assert_equal "lp", product.code
    assert_equal Date.new(2026, 10, 13), window.end_date

    data["window_end"] = "2026-10-20"
    assert_raises(WeeklyReport::Error) { WeeklyReport::Renderer.load_input(data, today: TODAY) }
  end
end
