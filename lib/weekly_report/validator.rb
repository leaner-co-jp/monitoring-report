# frozen_string_literal: true

module WeeklyReport
  # 完成形の Markdown がテンプレートとルールに従っているかを機械的に確かめる。
  #
  # レンダラの出力は必ずここを通る。手で直したレポートも `bin/weekly-report validate` で同じ基準にかけられる。
  # 照合の基準はテンプレートから毎回組み立てるので、テンプレートを直せば検証も追従する。
  class Validator
    Result = Struct.new(:errors, :warnings, :window, keyword_init: true)

    FIRED_EVENT = %r{(?:critical|warning) \d+回 / (?:最長)?\d+分}
    FIRED_CELL = /\A(?:発火なし|—|#{FIRED_EVENT}(?:、#{FIRED_EVENT})*)\z/
    COLORS = /[🔴🟡🟢⛔]/
    STATUS_LINE = /\A\*\*総合ステータス\*\*: (\S+) /
    TRIGGER_LINE = /\A\*\*アプリ調査トリガ\*\*: (\S+) — \S/
    INCIDENT_HEADING = %r{\A### 2\.(\d+) .+（対応要否 (\S+) (\S+) / .+）\z}
    MONITOR_LINK = %r{\]\(https://app\.datadoghq\.com/monitors/(\d+)\)}

    def initialize(markdown, root: WeeklyReport.root)
      @markdown = markdown
      @lines = markdown.lines(chomp: true)
      @root = root
      @errors = []
      @warnings = []
    end

    def run
      window = identify_window
      return result(nil) unless window

      skeleton_lines = Composer.new(window.product, root: @root).skeleton(window).lines(chomp: true)
      investigation = @lines.any? { |line| line.start_with?("## 2. ") }
      expected = expected_lines(skeleton_lines, investigation)

      check_leftovers
      check_headings(expected)
      check_fixed_lines(expected)
      check_metric_labels(expected)
      check_status_and_incidents(investigation)
      check_firing(investigation)
      check_unavailable_reasons
      check_monitor_references
      result(window)
    end

    private

    def result(window)
      Result.new(errors: @errors, warnings: @warnings, window: window)
    end

    def identify_window
      title_line = @lines.first.to_s
      unless title_line.start_with?("# ")
        @errors << "1行目がタイトル行（`# YYYY/MM/DD - MM/DD <固定部>`）ではない"
        return nil
      end
      Window.from_title(title_line.delete_prefix("# "), root: @root)
    rescue Error => e
      @errors << e.message
      nil
    end

    # §2 がない週はスケルトンから §2 を落とした形が期待値になる。
    def expected_lines(skeleton_lines, investigation)
      s2, separator = Composer.section2_range(skeleton_lines)
      return skeleton_lines if investigation

      skeleton_lines.take(s2) + skeleton_lines.drop(separator + 1)
    end

    def check_leftovers
      @errors << "埋められていないプレースホルダ `{{…}}` が残っている" if @markdown.match?(/\{\{|\}\}/)
      @errors << "記入ガイド（「ガイド」）が出力に残っている" if @markdown.include?("ガイド")
    end

    # 見出しの並びがテンプレートと一致すること（独自の節の追加・欠落・入れ替えを防ぐ）。
    def check_headings(expected)
      actual = normalize_headings(@lines)
      wanted = normalize_headings(expected)
      return if actual == wanted

      missing = wanted - actual
      extra = actual - wanted
      detail = []
      detail << "欠落: #{missing.join(' / ')}" unless missing.empty?
      detail << "テンプレートにない見出し: #{extra.join(' / ')}" unless extra.empty?
      detail << "順序が違う" if detail.empty?
      @errors << "見出しの構成がテンプレートと一致しない（#{detail.join('、')}）"
    end

    def normalize_headings(lines)
      headings = lines.select { |line| line.match?(/\A\#{1,6} /) }.drop(1)
      headings.map { |line| line.start_with?("### 2.") ? "### 2.N（インシデント）" : line }.chunk_while { |a, b| a == b }.map(&:first)
    end

    # テンプレートの固定行（値を埋める必要のない行）が、すべて同じ順序で出力に含まれていること。
    # 「色の意味」「評価ルール」などの固定文の言い換え・省略はここで検出される。
    def check_fixed_lines(expected)
      fixed = fixed_lines(expected)
      position = 0
      fixed.each do |line|
        found = (position...@lines.length).find { |i| @lines[i] == line }
        if found
          position = found + 1
        else
          @errors << "テンプレートの固定行が欠落・改変されているか順序が違う: #{line.strip[0, 80]}"
        end
      end
    end

    def fixed_lines(lines)
      in_incident = false
      lines.drop(1).reject do |line|
        in_incident = true if line.start_with?("### 2.")
        in_incident = false if line.start_with?("## 3. ") || line.strip == "---"
        line.strip.empty? || line.include?("{{") || (in_incident && MarkdownTable.row?(line))
      end
    end

    # 指標表の行（指標名）がテンプレートと過不足なく同じ順序で並んでいること。
    def check_metric_labels(expected)
      wanted = metric_tables(expected)
      actual = metric_tables(@lines)
      wanted.each_with_index do |(header, labels), i|
        actual_labels = actual[i]&.last
        next if actual_labels == labels

        @errors << "表「#{header}」の指標の行がテンプレートと一致しない（テンプレート: #{labels.size} 行 / 出力: #{actual_labels&.size || 0} 行）"
      end
    end

    def metric_tables(lines)
      MarkdownTable.ranges(lines).filter_map do |range|
        header = MarkdownTable.split(lines[range.begin])
        index = header.index("指標")
        next unless index

        [header.join(" | "), lines[(range.begin + 2)..range.end].map { |line| MarkdownTable.split(line)[index] }]
      end
    end

    def check_status_and_incidents(investigation)
      status = @lines.filter_map { |line| STATUS_LINE.match(line)&.captures&.first }.first
      @errors << "総合ステータスの色は 🟢 か 🔴（#{status.inspect}）" unless %w[🟢 🔴].include?(status)

      trigger = @lines.filter_map { |line| TRIGGER_LINE.match(line)&.captures&.first }.first
      @errors << "アプリ調査トリガは「ON — …」か「OFF — …」の形で書く" unless %w[ON OFF].include?(trigger)
      @errors << "アプリ調査トリガが ON なのに §2 調査がない" if trigger == "ON" && !investigation

      incidents = @lines.filter_map { |line| INCIDENT_HEADING.match(line)&.captures }
      if investigation && incidents.empty?
        @errors << "§2 調査があるのにインシデントの節（### 2.N … （対応要否 …））がない"
      end
      incidents.each_with_index do |(number, color, label), i|
        @errors << "§2 の節番号が連番になっていない（2.#{number}、期待値 2.#{i + 1}）" unless number.to_i == i + 1
        expected_label = Renderer::COLOR_LABELS[color]
        if expected_label.nil?
          @errors << "§2.#{number} の対応要否の色は 🟢 / 🟡 / 🔴 のいずれか（#{color}）"
        elsif expected_label != label
          @errors << "§2.#{number} の対応要否が色と合わない（#{color} は「#{expected_label}」）"
        end
      end

      red = incidents.any? { |(_, color, _)| color == "🔴" }
      if red && status != "🔴"
        @errors << "§2 に 🔴 の節があるのに総合ステータスが #{status}（max ルール: §2 の最も重い対応要否に合わせる）"
      elsif status == "🔴" && !red
        @errors << "総合ステータスが 🔴 なのに §2 に 🔴 の節がない（max ルール: 今週判断が必要なインシデントを §2 に書く）"
      end
    end

    # 台帳の「monitor発火」列: 書式（件数と継続時間だけ・色なし）と、§2 の有無との整合。
    def check_firing(investigation)
      fired_cells = []
      MarkdownTable.ranges(@lines).each do |range|
        header = MarkdownTable.split(@lines[range.begin])
        index = header.index("monitor発火")
        next unless index

        (range.begin + 2..range.end).each do |i|
          cells = MarkdownTable.split(@lines[i])
          fired_cells << [cells[1] || cells[0], cells[index].to_s]
        end
      end

      fired_cells.each do |label, cell|
        if cell.match?(COLORS)
          @errors << "monitor発火の列に色が付いている（#{label}: #{cell}）。発火は件数と継続時間で書く"
        elsif !cell.match?(FIRED_CELL)
          @errors << "monitor発火の書式が違う（#{label}: #{cell.inspect}）。" \
                     "「発火なし」か「critical N回 / N分」「warning N回 / 最長N分」を「、」でつなぐ"
        end
      end

      firing = fired_cells.reject { |_, cell| ["発火なし", "—"].include?(cell) }
      if !firing.empty? && !investigation
        @errors << "台帳に発火（#{firing.map(&:first).join(', ')}）があるのに §2 調査がない"
      elsif firing.empty? && investigation
        @warnings << "§2 調査があるが台帳の monitor発火 列に発火がない（台帳にない monitor の発火なら問題ない）"
      end
    end

    def check_unavailable_reasons
      count = @markdown.scan(/⚠️ 取得不可(?!: \S)/).size
      @errors << "「⚠️ 取得不可」の後に「: <理由>」がない箇所が #{count} 件ある" if count.positive?
    end

    # monitor は `[名前](https://app.datadoghq.com/monitors/ID)（#ID）` の形でだけ参照する。
    def check_monitor_references
      @markdown.scan(/#{MONITOR_LINK}(?!（#\1）)/).flatten.uniq.each do |id|
        @errors << "monitor #{id} のリンクの直後に「（##{id}）」がない"
      end
      bare = @markdown.gsub(/#{MONITOR_LINK}（#\1）/, "").scan(/#(\d{6,})/).flatten.uniq
      bare.each { |id| @errors << "monitor ID ##{id} がリンクなしで書かれている（`[名前](…/monitors/#{id})（##{id}）` の形にする）" }
      @errors << "monitor を「mon 12345」のような略記で書いている" if @markdown.match?(/\bmon \d+/)
    end
  end
end
