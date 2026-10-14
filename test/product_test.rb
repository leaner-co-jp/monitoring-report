# frozen_string_literal: true

require_relative "test_helper"

class ProductTest < Minitest::Test
  include TestHelper

  def test_reads_variables_and_blocks_for_every_product
    WeeklyReport::Product.all.each do |product|
      assert_match(/インフラモニタリング 週次レポート\z/, product.report_title)
      %w[targets monitors thresholds ledger signal-rows investigation-premises].each do |name|
        refute_empty product.block(name), "#{product.code}: {{P:#{name}}}"
      end
    end
  end

  def test_fj_team_tag_is_connect
    assert_equal "connect", product("fj").var("team")
  end

  def test_window_end_weekday
    assert_equal 2, product("lp").window_end_wday # 火
    assert_equal 4, product("pu").window_end_wday # 木
    assert_equal 4, product("fj").window_end_wday
  end

  def test_output_ids_are_normalized
    lp = product("lp")
    assert_equal "353daeae0b018043bd60000b0cef4826", lp.data_source_id
    assert_equal "353daeae0b0180528fa0c6c212b74441", lp.database_id
  end

  def test_block_does_not_swallow_separator
    refute_match(/---\s*\z/, product("lp").block("ledger"))
  end

  def test_unknown_product
    assert_raises(WeeklyReport::Error) { WeeklyReport::Product.load("xx") }
  end
end
