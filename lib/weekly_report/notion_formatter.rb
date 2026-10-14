# frozen_string_literal: true

module WeeklyReport
  # 検証済みの Markdown を Notion-flavored Markdown（notion-create-pages の content）に変換する。
  #
  # - タイトル行はページのタイトルプロパティに入れるので本文から外す
  # - パイプ表 → <table header-row="true">
  # - <aside> → <callout>（1行目の絵文字をアイコンにする）
  # - 行頭の4スペース字下げ → タブ
  # - `>` だけの行（Notion では空の引用ブロックになる）を落とす
  module NotionFormatter
    module_function

    def convert(markdown)
      lines = markdown.lines(chomp: true)
      lines.shift if lines.first&.start_with?("# ")
      out = []
      i = 0
      while i < lines.length
        line = lines[i]
        if line.start_with?("```")
          close = (i + 1...lines.length).find { |j| lines[j].start_with?("```") } || (lines.length - 1)
          out.concat(lines[i..close])
          i = close + 1
        elsif line.strip == "<aside>"
          close = (i + 1...lines.length).find { |j| lines[j].strip == "</aside>" } || lines.length
          out.concat(callout(lines[(i + 1)...close]))
          i = close + 1
        elsif MarkdownTable.row?(line)
          close = i
          close += 1 while close + 1 < lines.length && MarkdownTable.row?(lines[close + 1])
          out.concat(table(lines[i..close]))
          i = close + 1
        elsif line.strip == ">"
          i += 1
        else
          out << tabify(line)
          i += 1
        end
      end
      out.join("\n").gsub(/\n{3,}/, "\n\n").strip + "\n"
    end

    def callout(inner)
      content = inner.drop_while { |line| line.strip.empty? }
      icon = content.shift.to_s.strip
      body = convert(content.join("\n")).lines(chomp: true).reject { |line| line.strip.empty? }
      [%(<callout icon="#{icon}">), *body.map { |line| "\t#{line}" }, "</callout>"]
    end

    def table(rows)
      body = rows.reject { |row| MarkdownTable.separator?(row) }
      out = ['<table header-row="true">']
      body.each do |row|
        out << "\t<tr>"
        MarkdownTable.split(row).each { |cell| out << "\t\t<td>#{MarkdownTable.unescape(cell)}</td>" }
        out << "\t</tr>"
      end
      out << "</table>"
    end

    def tabify(line)
      indent = line[/\A(?: {4})*/]
      ("\t" * (indent.length / 4)) + line.delete_prefix(indent)
    end
  end
end
