# frozen_string_literal: true

require "minitest/autorun"
require "json"
require "tmpdir"
require_relative "../lib/weekly_report"

module TestHelper
  TODAY = Date.new(2026, 10, 14) # 水曜。LP は 10/07〜10/13、PU・FJ は 10/02〜10/08 が直近のクローズ済み週
  GENERATED_AT = Time.new(2026, 10, 14, 9, 0, 0, "+09:00")

  def product(code)
    WeeklyReport::Product.load(code)
  end

  def window(code)
    WeeklyReport::Window.latest_closed(product(code), today: TODAY)
  end

  # スタブの空欄を機械的に埋めた、発火のない週の入力
  def quiet_week(code)
    data = WeeklyReport::Stub.new(product(code), window(code)).build
    data.delete("_incident_example")
    fill_blanks(data)
    data["status"]["color"] = "🟢"
    data["trigger"]["state"] = "OFF"
    data["trigger"]["detail"] = "インフラ / SLO 異常なし"
    data["metrics"].each_value { |entry| entry["fired"] = "発火なし" if entry.key?("fired") }
    data
  end

  # 台帳の1行で critical が発火し、§2 にインシデントが1件ある週の入力
  def firing_week(code, color: "🔴")
    data = quiet_week(code)
    data["status"]["color"] = color == "🔴" ? "🔴" : "🟢"
    data["trigger"]["state"] = "ON"
    data["trigger"]["detail"] = "[API CPU](https://app.datadoghq.com/monitors/297262484)（#297262484）が critical"
    data["metrics"]["API メモリ max% / avg%"]["fired"] = "critical 1回 / 10分"
    data["incidents"] = [incident(color)]
    data
  end

  def incident(color = "🔴")
    {
      "title" => "API メモリの高騰",
      "color" => color,
      "firing" => "critical 1回 / 10分",
      "signal" => "[ECS API メモリ](https://app.datadoghq.com/monitors/297262485)（#297262485）が 火 13:07 に critical 発火 → 13:17 復旧",
      "primary" => "一次調査の結果",
      "correlation" => "相関調査の結果",
      "apm" => [],
      "orient" => "Orient の結果",
      "decide" => "§1 の 🔴 候補につながる",
      "links" => "[トレース](https://app.datadoghq.com/apm/traces?end=1791900000000&paused=true)"
    }
  end

  def render(code, data, root: WeeklyReport.root)
    WeeklyReport::Renderer.new(
      product: product(code), window: window(code), data: data, root: root, generated_at: GENERATED_AT
    ).render
  end

  def render_errors(code, data)
    render(code, data)
    flunk "ValidationError が発生するはず"
  rescue WeeklyReport::ValidationError => e
    e.errors
  end

  private

  def fill_blanks(node)
    case node
    when Hash
      node.each do |key, value|
        if value == ""
          node[key] = "#{key} の値"
        else
          fill_blanks(value)
        end
      end
    end
  end
end
