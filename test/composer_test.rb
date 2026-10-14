# frozen_string_literal: true

require_relative "test_helper"

class ComposerTest < Minitest::Test
  include TestHelper

  def skeleton(code)
    WeeklyReport::Composer.new(product(code)).skeleton(window(code))
  end

  def test_resolves_every_product_placeholder
    WeeklyReport::Product::CODES.each do |code|
      text = skeleton(code)
      refute_match(/\{\{P[.:]/, text, code)
      refute_match(/\{\{W\.(?!generated_at)/, text, code)
    end
  end

  def test_starts_at_title_and_drops_guides
    WeeklyReport::Product::CODES.each do |code|
      text = skeleton(code)
      assert text.start_with?("# #{window(code).title}\n"), code
      refute_includes text, "ガイド", code
      refute_includes text, "📋", code
      refute_includes text, "運用ガイド", code
    end
  end

  def test_keeps_domain_notes
    text = skeleton("fj")
    assert_includes text, "**調査時の前提**"
    assert_includes text, "防御シグナル含む。量と推移のみ"
  end

  def test_fills_window_values
    text = skeleton("lp")
    assert_includes text, "from_ts=1791298800000&to_ts=1791903599000"
    assert_includes text, "先週: 2026/09/30 00:00 JST 〜 2026/10/06 23:59 JST"
  end

  def test_headings_are_separated_by_blank_lines
    skeleton("lp").lines(chomp: true).each_cons(2) do |before, line|
      next unless line.start_with?("#")

      assert_equal "", before, "見出しの直前が空行でない: #{line}"
    end
  end
end
