# frozen_string_literal: true

module WeeklyReport
  # templates/<lp|pu|fj>.md の変数表（{{P.xxx}}）と差し込みブロック（{{P:xxx}}）。
  # 固有値の唯一の真実はテンプレート側なので、ここでは値を持たずに毎回読む。
  class Product
    CODES = %w[lp pu fj].freeze
    WEEKDAYS = %w[日 月 火 水 木 金 土].freeze

    VAR_ROW = /\A\|\s*`\{\{P\.([a-z_]+)\}\}`\s*\|\s*(.*?)\s*\|\s*\z/
    BLOCK_HEADING = /\A## \{\{P:([a-z-]+)\}\}\s*\z/

    attr_reader :code, :vars, :blocks

    def self.load(code, root: WeeklyReport.root)
      unless CODES.include?(code)
        raise Error, "未知のプロダクト: #{code.inspect}（#{CODES.join(' / ')} のいずれか）"
      end

      new(code, File.read(File.join(root, "templates", "#{code}.md")))
    end

    def self.all(root: WeeklyReport.root)
      CODES.map { |code| load(code, root: root) }
    end

    def initialize(code, source)
      @code = code
      lines = source.lines(chomp: true)
      @vars = parse_vars(lines)
      @blocks = parse_blocks(lines)
    end

    def var(name)
      vars.fetch(name) { raise Error, "templates/#{code}.md に {{P.#{name}}} がない" }
    end

    def block(name)
      blocks.fetch(name) { raise Error, "templates/#{code}.md に ## {{P:#{name}}} ブロックがない" }
    end

    def report_title
      var("report_title")
    end

    def title_prop
      var("title_prop")
    end

    def window_end_wday
      WEEKDAYS.index(var("window_end_ja")) ||
        raise(Error, "templates/#{code}.md の window_end_ja が曜日1文字ではない: #{var('window_end_ja')}")
    end

    # 出力先の data source ID（ハイフンなし）。Notion へ書き込む先の判定に使う。
    def data_source_id
      normalize_id(var("datasource"))
    end

    def database_id
      normalize_id(var("output_db"))
    end

    private

    def normalize_id(value)
      value.delete_prefix("collection://").split("/").last.split("?").first.delete("-")
    end

    def parse_vars(lines)
      lines.each_with_object({}) do |line, vars|
        match = VAR_ROW.match(line)
        vars[match[1]] = match[2] if match
      end
    end

    # `## {{P:name}}` 見出しから次の見出しまでがブロック。末尾の区切り線と空行は落とす。
    def parse_blocks(lines)
      blocks = {}
      current = nil
      lines.each do |line|
        if (match = BLOCK_HEADING.match(line))
          current = blocks[match[1]] = []
        elsif current
          current << line
        end
      end
      blocks.transform_values { |block_lines| trim(block_lines) }
    end

    def trim(lines)
      lines = lines.dup
      lines.shift while lines.first&.strip&.empty?
      lines.pop while lines.last && (lines.last.strip.empty? || lines.last.strip == "---")
      lines.join("\n")
    end
  end
end
