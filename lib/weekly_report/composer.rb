# frozen_string_literal: true

module WeeklyReport
  # templates/report.md と templates/<product>.md を合成して「スケルトン」を作る。
  #
  # スケルトン = 運用ガイドと「ガイド:」を除き、{{P.}} {{P:}} {{W.}} をすべて解決したもの。
  # 残るのはエージェントが埋める {{R.}} {{I.}}、自動導出の {{X.}}、表の単位プレースホルダだけ。
  class Composer
    TITLE_LINE = /\A# \{\{W\.title_start\}\}/
    GUIDE_BULLET = /\A(\s*)- (?:ガイド:|📋)/
    GUIDE_ASIDE_MARKER = "ガイド（出力しない）"

    attr_reader :product

    def initialize(product, root: WeeklyReport.root)
      @product = product
      @template = File.read(File.join(root, "templates", "report.md"))
    end

    # generated_at を省略すると {{W.generated_at}} を残す（検証で固定行の照合から外すため）。
    def skeleton(window, generated_at: "{{W.generated_at}}")
      lines = @template.lines(chomp: true)
      start = lines.index { |line| TITLE_LINE.match?(line) }
      raise Error, "templates/report.md にタイトル行 `# {{W.title_start}} …` がない" unless start

      text = strip_guides(lines[start..]).join("\n")
      text = substitute_blocks(text)
      text = substitute_vars(text)
      text = substitute_window(text, window.slot_values(generated_at: generated_at))
      leftover = text.scan(/\{\{(?:P[.:]|W\.(?!generated_at))[^}]*\}\}/).uniq
      raise Error, "合成後に解決できないプレースホルダが残った: #{leftover.join(', ')}" unless leftover.empty?

      squeeze_blank_lines(text.lines(chomp: true)).join("\n") + "\n"
    end

    # §2 の範囲。[見出し行, §3 直前の区切り線] の添字を返す。
    def self.section2_range(lines)
      s2 = lines.index { |line| line.start_with?("## 2. ") }
      s3 = lines.index { |line| line.start_with?("## 3. ") }
      return nil unless s2 && s3

      separator = (s2...s3).to_a.reverse.find { |i| lines[i].strip == "---" }
      raise Error, "§2 と §3 の間に区切り線 `---` がない" unless separator

      [s2, separator]
    end

    private

    # 「- ガイド: …」の箇条とその字下げされた中身、および「ガイド（出力しない）」を含む aside を落とす。
    def strip_guides(lines)
      out = []
      i = 0
      while i < lines.length
        line = lines[i]
        if (match = GUIDE_BULLET.match(line))
          indent = match[1].length
          i += 1
          i += 1 while i < lines.length && (lines[i].strip.empty? || indent_of(lines[i]) > indent)
          out << "" # 後ろの見出しや段落と地続きにならないように区切りを残す（連続する空行は後で畳む）
          next
        end
        if line.strip == "<aside>"
          close = (i...lines.length).find { |j| lines[j].strip == "</aside>" }
          raise Error, "templates/report.md の <aside> が閉じていない（#{i + 1} 行目付近）" unless close

          if lines[i..close].any? { |aside_line| aside_line.include?(GUIDE_ASIDE_MARKER) }
            i = close + 1
            next
          end
        end
        out << line
        i += 1
      end
      out
    end

    def substitute_blocks(text)
      text.gsub(/\{\{P:([a-z-]+)\}\}/) { product.block(Regexp.last_match(1)) }
    end

    def substitute_vars(text)
      text.gsub(/\{\{P\.([a-z_]+)\}\}/) { product.var(Regexp.last_match(1)) }
    end

    def substitute_window(text, values)
      text.gsub(/\{\{W\.([a-z_]+)\}\}/) do
        name = Regexp.last_match(1)
        values.fetch(name) { raise Error, "未知のウインドウ値: {{W.#{name}}}" }
      end
    end

    def indent_of(line)
      line[/\A */].length
    end

    def squeeze_blank_lines(lines)
      lines.each_with_object([]) do |line, out|
        next if line.strip.empty? && (out.empty? || out.last.strip.empty?)

        out << line.rstrip
      end.tap { |out| out.pop while out.last&.empty? }
    end
  end
end
