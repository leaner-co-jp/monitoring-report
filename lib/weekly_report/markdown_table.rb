# frozen_string_literal: true

module WeeklyReport
  # パイプ区切りの Markdown 表を扱う。
  # テンプレートのセルには `{{発火なし|critical N回 / N分}}` のように `{{ }}` 内のパイプがあるので、
  # `{{ }}` の内側とエスケープ済みの `\|` では区切らない。
  module MarkdownTable
    module_function

    def row?(line)
      line.start_with?("|")
    end

    def separator?(line)
      split(line).all? { |cell| cell.match?(/\A:?-{3,}:?\z/) }
    end

    def split(line)
      body = line.strip.delete_prefix("|")
      body = body.delete_suffix("|") unless body.end_with?("\\|")
      cells = [+""]
      depth = 0
      i = 0
      while i < body.length
        pair = body[i, 2]
        if pair == "{{"
          depth += 1
        elsif pair == "}}" && depth.positive?
          depth -= 1
        elsif pair == "\\|"
          cells.last << pair
          i += 2
          next
        elsif body[i] == "|" && depth.zero?
          cells << +""
          i += 1
          next
        end
        if %w[{{ }}].include?(pair)
          cells.last << pair
          i += 2
        else
          cells.last << body[i]
          i += 1
        end
      end
      cells.map(&:strip)
    end

    def join(cells)
      "| #{cells.join(' | ')} |"
    end

    # 行配列の中の表を [開始行, 終了行] の範囲で列挙する（終了行を含む）。
    def ranges(lines)
      result = []
      i = 0
      while i < lines.length
        if row?(lines[i])
          j = i
          j += 1 while j + 1 < lines.length && row?(lines[j + 1])
          result << (i..j)
          i = j + 1
        else
          i += 1
        end
      end
      result
    end

    def escape(value)
      value.gsub(/(?<!\\)\|/, "\\|")
    end

    def unescape(value)
      value.gsub("\\|", "|")
    end
  end
end
