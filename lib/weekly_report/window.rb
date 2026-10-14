# frozen_string_literal: true

require "date"

module WeeklyReport
  # 対象ウインドウ（直近のクローズ済み7日間）。時刻はすべて JST で計算する。
  class Window
    JST = "+09:00"

    attr_reader :product, :start_date, :end_date

    def self.today_jst
      Time.now.getlocal(JST).to_date
    end

    # today 時点で最後に閉じた週。今日が終端曜日でも、その日はまだ閉じていないので先週分になる。
    def self.latest_closed(product, today: today_jst)
      end_date = today - 1
      end_date -= 1 until end_date.wday == product.window_end_wday
      new(product, end_date)
    end

    def self.ending(product, end_date, today: today_jst)
      end_date = Date.iso8601(end_date.to_s)
      unless end_date.wday == product.window_end_wday
        raise Error, "#{product.code.upcase} の週は#{product.var('window_ja')}。" \
                     "#{end_date} は#{Product::WEEKDAYS[end_date.wday]}曜日なので週の終端ではない"
      end
      if today && end_date >= today
        raise Error, "#{end_date} で終わる週はまだ閉じていない（partial-window）。累積系メトリクスを過少計上するので生成しない"
      end

      new(product, end_date)
    end

    # レポートタイトル（`YYYY/MM/DD - MM/DD <固定部>`）からプロダクトとウインドウを特定する。
    def self.from_title(title, root: WeeklyReport.root)
      match = %r{\A(\d{4})/(\d{2})/(\d{2}) - (\d{2})/(\d{2}) (.+)\z}.match(title.to_s)
      raise Error, "タイトルが固定形式 `YYYY/MM/DD - MM/DD <固定部>` ではない: #{title.inspect}" unless match

      product = Product.all(root: root).find { |candidate| candidate.report_title == match[6] }
      raise Error, "タイトルの固定部がどのプロダクトとも一致しない: #{match[6].inspect}" unless product

      start_date = Date.new(match[1].to_i, match[2].to_i, match[3].to_i)
      window = ending(product, start_date + 6, today: nil)
      unless window.title == title
        raise Error, "タイトルの期間が7日間になっていない: #{title.inspect}（正しくは #{window.title.inspect}）"
      end

      window
    end

    def initialize(product, end_date)
      @product = product
      @end_date = end_date
      @start_date = end_date - 6
    end

    def previous
      Window.new(product, end_date - 7)
    end

    def title
      "#{start_date.strftime('%Y/%m/%d')} - #{end_date.strftime('%m/%d')} #{product.report_title}"
    end

    def from_ms
      epoch_ms(start_date, 0, 0, 0)
    end

    def to_ms
      epoch_ms(end_date, 23, 59, 59)
    end

    # テンプレートの {{W.xxx}} に差し込む値
    def slot_values(generated_at:)
      prev = previous
      {
        "title_start" => start_date.strftime("%Y/%m/%d"),
        "title_end" => end_date.strftime("%m/%d"),
        "from_ms" => from_ms.to_s,
        "to_ms" => to_ms.to_s,
        "prev_from_ms" => prev.from_ms.to_s,
        "prev_to_ms" => prev.to_ms.to_s,
        "from_jst" => "#{start_date.strftime('%Y/%m/%d')} 00:00",
        "to_jst" => "#{end_date.strftime('%Y/%m/%d')} 23:59",
        "prev_from_jst" => "#{prev.start_date.strftime('%Y/%m/%d')} 00:00",
        "prev_to_jst" => "#{prev.end_date.strftime('%Y/%m/%d')} 23:59",
        "prev_title_range" => "#{prev.start_date.strftime('%m/%d')} - #{prev.end_date.strftime('%m/%d')}",
        "generated_at" => generated_at
      }
    end

    def to_h
      prev = previous
      {
        "start" => start_date.iso8601,
        "end" => end_date.iso8601,
        "from_s" => from_ms / 1000,
        "to_s" => to_ms / 1000,
        "from_ms" => from_ms,
        "to_ms" => to_ms,
        "prev_start" => prev.start_date.iso8601,
        "prev_end" => prev.end_date.iso8601,
        "prev_from_s" => prev.from_ms / 1000,
        "prev_to_s" => prev.to_ms / 1000,
        "prev_from_ms" => prev.from_ms,
        "prev_to_ms" => prev.to_ms
      }
    end

    private

    def epoch_ms(date, hour, minute, second)
      Time.new(date.year, date.month, date.day, hour, minute, second, JST).to_i * 1000
    end
  end
end
