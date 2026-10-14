# frozen_string_literal: true

module WeeklyReport
  # スケルトンにエージェントの JSON を流し込んで完成形の Markdown を作る。
  #
  # 構成・固定文・節番号・§2 の有無・案内文はここで決まる。エージェントが決めるのは値と所見だけ。
  # 足りない値・余計なキー・固定セルの書き換えは、すべて集めてから ValidationError で返す。
  class Renderer
    # 指標表（「指標」列を持つ表）の列見出し → metrics[指標] のキー
    METRIC_COLUMNS = {
      "今週" => "this",
      "先週" => "prev",
      "変化" => "change",
      "monitor発火" => "fired",
      "校正メモ" => "memo",
      "解釈（Orient）" => "orient"
    }.freeze

    # §2 の APM トレース調査表の列見出し → incidents[].apm[] のキー
    APM_COLUMNS = {
      "区分" => "category",
      "resource_name" => "resource",
      "平常 p50" => "baseline_p50",
      "ウインドウ内 p50" => "window_p50",
      "変化" => "change"
    }.freeze

    COLOR_LABELS = { "🟢" => "記録のみ", "🟡" => "次週判断", "🔴" => "今週判断" }.freeze

    # JSON のうち、スロットではなくレンダラ自身が読むキー
    CONTROL_KEYS = %w[product window_end metrics incidents].freeze

    CLOSING_GUIDE_WITH_INVESTIGATION =
      "以降は詳細確認用です。monitor 発火の調査内容を確認したい場合は §2 調査を、" \
      "数値の週次記録と前回 Decide / Act の反映状況を確認したい場合は §3 付録を参照してください。"
    CLOSING_GUIDE_WITHOUT_INVESTIGATION =
      "以降は詳細確認用です。数値の週次記録と前回 Decide / Act の反映状況を確認したい場合は §3 付録を参照してください。"

    def self.load_input(data, root: WeeklyReport.root, today: Window.today_jst)
      raise Error, "入力 JSON のトップレベルがオブジェクトではない" unless data.is_a?(Hash)

      product = Product.load(data["product"].to_s, root: root)
      window_end = data["window_end"] or raise Error, "入力 JSON に window_end（YYYY-MM-DD）がない"
      window = Window.ending(product, window_end, today: today)
      [product, window]
    end

    attr_reader :product, :window, :data

    def initialize(product:, window:, data:, root: WeeklyReport.root, generated_at: Time.now.getlocal(Window::JST))
      @product = product
      @window = window
      @data = data
      @root = root
      @generated_at = generated_at.strftime("%Y-%m-%dT%H:%M:%S%:z")
      @errors = []
      @used_paths = []
      @used_metrics = []
    end

    def render
      skeleton = Composer.new(product, root: @root).skeleton(window, generated_at: @generated_at)
      lines = skeleton.lines(chomp: true)
      lines = render_investigation(lines)
      lines = fill_metric_tables(lines)
      lines = fill_slots(lines, "R", data, "")
      lines = fill_derived(lines)
      check_unused_keys
      raise ValidationError, @errors unless @errors.empty?

      markdown = lines.join("\n").gsub(/\n{3,}/, "\n\n") + "\n"
      result = Validator.new(markdown, root: @root).run
      raise ValidationError, result.errors unless result.errors.empty?

      markdown
    end

    private

    def incidents
      value = data.fetch("incidents", [])
      return value if value.is_a?(Array) && value.all? { |incident| incident.is_a?(Hash) }

      @errors << "incidents は §2 のインシデント（オブジェクト）の配列にする（発火がない週は []）"
      []
    end

    # §2: インシデントがなければ節ごと落とし、あれば1件ずつ描画して 2.1, 2.2 … と番号を振る。
    def render_investigation(lines)
      s2, separator = Composer.section2_range(lines)
      return lines.take(s2) + lines.drop(separator + 1) if incidents.empty?

      first = (s2...separator).find { |i| lines[i].start_with?("### 2.") }
      raise Error, "templates/report.md の §2 にインシデント見出し `### 2.…` がない" unless first

      body = lines[first...separator]
      rendered = incidents.each_with_index.flat_map do |incident, index|
        render_incident(body, incident, index) + [""]
      end
      lines.take(first) + rendered + lines.drop(separator)
    end

    def render_incident(body, incident, index)
      label = "incidents[#{index}]"
      color = incident["color"].to_s
      @errors << "#{label}.color は 🟢 / 🟡 / 🔴 のいずれか（#{color.inspect}）" unless COLOR_LABELS.key?(color)

      lines = fill_apm_table(body, incident, label)
      lines = fill_slots(lines, "I", incident, "#{label}.")
      lines = lines.map do |line|
        line.gsub("{{X.incident_number}}", (index + 1).to_s)
            .gsub("{{X.incident_color_label}}", COLOR_LABELS.fetch(color, "?"))
      end
      used = @used_paths.filter_map { |path| path.delete_prefix("#{label}.") if path.start_with?("#{label}.") }
      (incident.keys - used - %w[apm]).reject { |key| key.start_with?("_") }.each do |key|
        @errors << "#{label}.#{key} はテンプレートにないキー（打ち間違いか、テンプレート側の変更漏れ）"
      end
      lines
    end

    def fill_apm_table(lines, incident, label)
      range = MarkdownTable.ranges(lines).first
      return lines unless range

      rows = incident.fetch("apm", [])
      unless rows.is_a?(Array) && rows.all? { |row| row.is_a?(Hash) }
        @errors << "#{label}.apm は行（オブジェクト）の配列にする（APM 調査をしていなければ []）"
        rows = []
      end
      if rows.empty?
        before = lines.take(range.begin)
        before.pop if before.last&.empty?
        return before + lines.drop(range.end + 1)
      end

      table = lines[range]
      header = MarkdownTable.split(table[0])
      rendered = rows.each_with_index.map do |row, i|
        cells = header.map do |column|
          key = APM_COLUMNS.fetch(column) { raise Error, "APM 表の未知の列: #{column}" }
          cell_value(row[key], "#{label}.apm[#{i}].#{key}")
        end
        unknown = row.keys - APM_COLUMNS.values
        unknown.each { |key| @errors << "#{label}.apm[#{i}].#{key} は APM 表にない列" }
        MarkdownTable.join(cells)
      end
      lines.take(range.begin) + table.take(2) + rendered + lines.drop(range.end + 1)
    end

    # 「指標」列を持つ表は、その名前で metrics から値を引く。
    #   - `{{…}}` のセル: 必須
    #   - 空のセル: 任意（なければ空のまま）
    #   - それ以外: テンプレートの固定値。JSON で別の値を入れようとしたらエラー
    def fill_metric_tables(lines)
      metrics = data.fetch("metrics", {})
      unless metrics.is_a?(Hash)
        @errors << "metrics は「指標名 → {this, prev, change, …}」のオブジェクトにする"
        metrics = {}
      end
      lines = lines.dup
      MarkdownTable.ranges(lines).each do |range|
        header = MarkdownTable.split(lines[range.begin])
        label_index = header.index("指標")
        next unless label_index

        (range.begin + 2..range.end).each do |i|
          lines[i] = fill_metric_row(header, label_index, MarkdownTable.split(lines[i]), metrics)
        end
      end
      lines
    end

    def fill_metric_row(header, label_index, cells, metrics)
      label = cells[label_index]
      entry = metrics[label]
      needs_values = cells.any? { |cell| cell.include?("{{") }
      if needs_values && !entry.is_a?(Hash)
        @errors << "metrics[#{label.inspect}] がない（#{required_keys(header, cells).join(', ')} が必要）"
        entry = {}
      end
      entry ||= {}
      @used_metrics << label if metrics.key?(label)

      filled = cells.each_with_index.map do |cell, j|
        key = METRIC_COLUMNS[header[j]]
        next cell if j == label_index || key.nil?

        path = "metrics[#{label.inspect}].#{key}"
        if cell.include?("{{")
          cell_value(entry[key], path)
        elsif cell.empty?
          entry.key?(key) ? cell_value(entry[key], path, required: false) : ""
        else
          if entry.key?(key) && entry[key] != cell
            @errors << "#{path} はテンプレートの固定値 #{cell.inspect} なので書き換えられない（#{entry[key].inspect}）"
          end
          cell
        end
      end
      MarkdownTable.join(filled)
    end

    def required_keys(header, cells)
      cells.each_with_index.filter_map { |cell, j| METRIC_COLUMNS[header[j]] if cell.include?("{{") }
    end

    def cell_value(value, path, required: true)
      unless value.is_a?(String)
        @errors << "#{path} がない（文字列で書く）" if required || !value.nil?
        return ""
      end
      if required && value.strip.empty?
        @errors << "#{path} が空（取得できなかった場合は「⚠️ 取得不可: <理由>」と書く）"
      end
      @errors << "#{path} に改行がある（表のセルは1行）" if value.include?("\n")
      MarkdownTable.escape(value.strip)
    end

    # {{NS.path}} は文字列、行全体が `- {{NS.path[]}}` のものは文字列配列を箇条書きに展開する。
    def fill_slots(lines, namespace, source, prefix)
      list_slot = /\A(\s*)- \{\{#{namespace}\.([a-z0-9_.]+)\[\](?:=([^}]*))?\}\}\s*\z/
      scalar_slot = /\{\{#{namespace}\.([a-z0-9_.]+)\}\}/
      lines.flat_map do |line|
        if (match = list_slot.match(line))
          indent, path, empty_text = match.captures
          items = fetch_list(source, path, "#{prefix}#{path}")
          next ["#{indent}- #{empty_text || '該当なし'}"] if items.empty?

          items.map { |item| "#{indent}- #{item}" }
        elsif line.match?(/\{\{#{namespace}\.[a-z0-9_.]+\[\]/)
          raise Error, "配列スロットは行全体を `- {{#{namespace}.…[]}}` にする: #{line}"
        else
          line.gsub(scalar_slot) { fetch_string(source, Regexp.last_match(1), "#{prefix}#{Regexp.last_match(1)}") }
        end
      end
    end

    def fill_derived(lines)
      guide = incidents.empty? ? CLOSING_GUIDE_WITHOUT_INVESTIGATION : CLOSING_GUIDE_WITH_INVESTIGATION
      lines.map { |line| line.gsub("{{X.closing_guide}}", guide) }
    end

    def dig(source, path)
      path.split(".").reduce(source) { |node, key| node.is_a?(Hash) ? node[key] : nil }
    end

    def fetch_string(source, path, label)
      @used_paths << label
      value = dig(source, path)
      if !value.is_a?(String) || value.strip.empty?
        @errors << "#{label} がない（空でない文字列で書く）"
        return ""
      end
      value.strip
    end

    def fetch_list(source, path, label)
      @used_paths << label
      value = dig(source, path)
      unless value.is_a?(Array) && value.all? { |item| item.is_a?(String) }
        @errors << "#{label} がない（文字列の配列で書く。該当がなければ []）"
        return []
      end
      value.each_with_index.filter_map do |item, i|
        if item.strip.empty?
          @errors << "#{label}[#{i}] が空"
          next
        end
        @errors << "#{label}[#{i}] に改行がある（箇条書きの1行に収める）" if item.include?("\n")
        item.strip
      end
    end

    # テンプレートにないキーは打ち間違いの可能性が高い（書いたつもりの値が消える）のでエラーにする。
    def check_unused_keys
      leaf_paths(data.reject { |key, _| CONTROL_KEYS.include?(key) }).each do |path|
        next if @used_paths.include?(path)

        @errors << "#{path} はテンプレートにないキー（打ち間違いか、テンプレート側の変更漏れ）"
      end
      metrics = data.fetch("metrics", {})
      return unless metrics.is_a?(Hash)

      (metrics.keys - @used_metrics).each do |label|
        @errors << "metrics[#{label.inspect}] はどの表にもない指標（指標名はテンプレートの表と一字一句合わせる）"
      end
    end

    def leaf_paths(node, prefix = nil)
      return [] if prefix&.split(".")&.last&.start_with?("_")
      return [prefix] unless node.is_a?(Hash)

      node.flat_map { |key, value| key.start_with?("_") ? [] : leaf_paths(value, [prefix, key].compact.join(".")) }
    end
  end
end
