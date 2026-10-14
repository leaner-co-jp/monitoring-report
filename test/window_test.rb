# frozen_string_literal: true

require_relative "test_helper"

class WindowTest < Minitest::Test
  include TestHelper

  def test_lp_on_wednesday_takes_the_week_ending_yesterday
    w = WeeklyReport::Window.latest_closed(product("lp"), today: Date.new(2026, 10, 14))
    assert_equal Date.new(2026, 10, 7), w.start_date
    assert_equal Date.new(2026, 10, 13), w.end_date
    assert_equal "2026/10/07 - 10/13 リーナー見積インフラモニタリング 週次レポート", w.title
  end

  def test_week_is_not_closed_on_its_last_day
    w = WeeklyReport::Window.latest_closed(product("lp"), today: Date.new(2026, 10, 13))
    assert_equal Date.new(2026, 10, 6), w.end_date
  end

  def test_pu_and_fj_end_on_thursday
    w = WeeklyReport::Window.latest_closed(product("pu"), today: Date.new(2026, 10, 16))
    assert_equal Date.new(2026, 10, 9), w.start_date
    assert_equal Date.new(2026, 10, 15), w.end_date
  end

  def test_epoch_ms_is_jst
    w = window("lp")
    assert_equal 1_791_298_800_000, w.from_ms # 2026-10-07 00:00:00 +09:00
    assert_equal 1_791_903_599_000, w.to_ms   # 2026-10-13 23:59:59 +09:00
    assert_equal w.from_ms - (7 * 86_400_000), w.previous.from_ms
  end

  def test_rejects_partial_window
    error = assert_raises(WeeklyReport::Error) do
      WeeklyReport::Window.ending(product("lp"), "2026-10-13", today: Date.new(2026, 10, 13))
    end
    assert_match(/partial-window/, error.message)
  end

  def test_rejects_wrong_end_weekday
    assert_raises(WeeklyReport::Error) do
      WeeklyReport::Window.ending(product("lp"), "2026-10-14", today: Date.new(2026, 10, 20))
    end
  end

  def test_from_title_identifies_product_and_window
    w = WeeklyReport::Window.from_title("2026/10/02 - 10/08 リーナーコネクトインフラモニタリング 週次レポート")
    assert_equal "fj", w.product.code
    assert_equal Date.new(2026, 10, 8), w.end_date
  end

  def test_from_title_rejects_the_drifted_format
    # 2026-10-14 の自動実行で実際に出力された形式
    assert_raises(WeeklyReport::Error) do
      WeeklyReport::Window.from_title("リーナー見積インフラモニタリング 週次レポート 2026/10/07〜10/13")
    end
  end

  def test_from_title_rejects_non_seven_day_range
    assert_raises(WeeklyReport::Error) do
      WeeklyReport::Window.from_title("2026/10/07 - 10/14 リーナー見積インフラモニタリング 週次レポート")
    end
  end
end
