# frozen_string_literal: true

# 週次インフラレポートの決定的な部分（合成・描画・検証）を担うライブラリ。
# エージェントは Datadog から集めた値と所見を JSON に書くだけにし、
# 構成・固定文・書式はここで機械的に組み立てて検証する。
module WeeklyReport
  class Error < StandardError; end

  # 複数の検証エラーをまとめて返す。エージェントが一度に全部直せるようにするため。
  class ValidationError < Error
    attr_reader :errors

    def initialize(errors)
      @errors = errors
      super("#{errors.size} 件の問題があります:\n#{errors.map { |e| "- #{e}" }.join("\n")}")
    end
  end

  def self.root
    File.expand_path("..", __dir__)
  end
end

require_relative "weekly_report/markdown_table"
require_relative "weekly_report/product"
require_relative "weekly_report/window"
require_relative "weekly_report/composer"
require_relative "weekly_report/renderer"
require_relative "weekly_report/validator"
require_relative "weekly_report/notion_formatter"
require_relative "weekly_report/stub"
require_relative "weekly_report/approval"
