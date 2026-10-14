# frozen_string_literal: true

module WeeklyReport
  # エージェントが埋める入力 JSON の雛形を、テンプレートのスロットから組み立てる。
  # テンプレートから毎回生成するので、雛形とテンプレートがずれることはない。
  class Stub
    def initialize(product, window, root: WeeklyReport.root)
      @product = product
      @window = window
      @root = root
    end

    def build
      lines = Composer.new(@product, root: @root).skeleton(@window).lines(chomp: true)
      data = {
        "_guide" => "各スロットの書き方は templates/report.md の「ガイド:」、全体の規則は " \
                    "skills/weekly-infra-report/references/output.md。incidents の要素は _incident_example の形。" \
                    "`_` で始まるキーは render が無視する。",
        "product" => @product.code,
        "window_end" => @window.end_date.iso8601
      }
      lines.join("\n").scan(/\{\{R\.([a-z0-9_.]+)(\[\])?/).each do |path, list|
        assign(data, path.split("."), list ? [] : "")
      end
      data["metrics"] = metrics(lines)
      data["incidents"] = []
      data["_incident_example"] = incident_example(lines)
      data
    end

    private

    def assign(data, keys, value)
      *parents, last = keys
      node = parents.reduce(data) { |hash, key| hash[key] ||= {} }
      node[last] = value
    end

    # 指標表の各行について、埋める必要のある列だけを並べる（複数の表に出る指標はキーを合算する）。
    def metrics(lines)
      MarkdownTable.ranges(lines).each_with_object({}) do |range, result|
        header = MarkdownTable.split(lines[range.begin])
        label_index = header.index("指標")
        next unless label_index

        lines[(range.begin + 2)..range.end].each do |row|
          cells = MarkdownTable.split(row)
          header.each_with_index do |column, j|
            key = Renderer::METRIC_COLUMNS[column]
            next unless key && (cells[j].include?("{{") || cells[j].empty?)

            (result[cells[label_index]] ||= {})[key] = ""
          end
        end
      end
    end

    def incident_example(lines)
      s2, separator = Composer.section2_range(lines)
      section = lines[s2..separator].join("\n")
      example = section.scan(/\{\{I\.([a-z0-9_]+)\}\}/).flatten.uniq.to_h { |key| [key, ""] }
      example["apm"] = [Renderer::APM_COLUMNS.values.to_h { |key| [key, ""] }]
      example
    end
  end
end
