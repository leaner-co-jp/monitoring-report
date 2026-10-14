# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "time"

module WeeklyReport
  # 検証を通った本文だけを Notion に書き込めるようにする仕組み。
  #
  # `render` が検証済みの本文のハッシュを承認済みとして記録し、Claude Code の PreToolUse hook（`guard`）が
  # レポート DB への書き込みのたびに、本文がその記録と一致するかを確かめる。手組みの本文や、検証後に
  # 書き換えた本文は一致しないので書き込めない。
  module Approval
    module_function

    # WEEKLY_REPORT_APPROVAL_DIR はテスト用（本物の承認記録を汚さない）
    def directory(root)
      ENV.fetch("WEEKLY_REPORT_APPROVAL_DIR") { File.join(root, "tmp", "weekly-report", "approved") }
    end

    # Notion 側で空行は落ちるので、空行と行末の空白は比較に含めない。
    def normalize(content)
      content.to_s.gsub("\r\n", "\n").lines(chomp: true).map(&:rstrip).reject(&:empty?)
    end

    def digest(content)
      Digest::SHA256.hexdigest(normalize(content).join("\n"))
    end

    def approve!(root, content:, title:, product:)
      FileUtils.mkdir_p(directory(root))
      record = {
        "title" => title,
        "product" => product.code,
        "title_prop" => product.title_prop,
        "approved_at" => Time.now.getlocal(Window::JST).iso8601,
        "content" => content
      }
      File.write(File.join(directory(root), "#{digest(content)}.json"), JSON.pretty_generate(record))
      record
    end

    def lookup(root, content)
      path = File.join(directory(root), "#{digest(content)}.json")
      File.exist?(path) ? JSON.parse(File.read(path)) : nil
    end

    # 写し間違いを直せるように、そのプロダクトで最後に承認した本文と最初に食い違う行を返す。
    def first_difference(root, content, product)
      latest = Dir[File.join(directory(root), "*.json")]
               .map { |file| JSON.parse(File.read(file)) }
               .select { |record| record["product"] == product.code }
               .max_by { |record| record["approved_at"].to_s }
      return nil unless latest

      expected = normalize(latest["content"])
      actual = normalize(content)
      index = (0...[expected.size, actual.size].max).find { |i| expected[i] != actual[i] }
      index && { "line" => index + 1, "expected" => expected[index], "actual" => actual[index] }
    end
  end

  # PreToolUse hook の本体。hook の入力 JSON を受け取り、書き込みを止めるべきならその理由を返す。
  class Guard
    REPORT_MARKER = "本レポートの全体報告はここで終了です。"

    def initialize(root: WeeklyReport.root)
      @root = root
      @products = Product.all(root: root)
    end

    # 止める理由（文字列）か nil を返す
    def check(event)
      tool = event["tool_name"].to_s
      input = event["tool_input"] || {}
      if tool.end_with?("notion-create-pages")
        check_create(input)
      elsif tool.end_with?("notion-update-page")
        check_update(input)
      end
    end

    private

    def check_create(input)
      product = report_product(input["parent"])
      return nil unless product

      Array(input["pages"]).each_with_index do |page, i|
        content = page["content"].to_s
        record = Approval.lookup(@root, content)
        return unapproved_message("pages[#{i}].content", product, content) unless record

        title = (page["properties"] || {})[product.title_prop]
        if title != record["title"]
          return "#{product.title_prop} が承認済みのタイトルと違う（#{title.inspect}）。" \
                 "`#{record['title']}` をそのまま指定する。"
        end
      end
      nil
    end

    # ページの親が分からないので、レポート本文と分かる全置換だけを確かめる。
    def check_update(input)
      return nil unless input["command"] == "replace_content"

      content = input["new_str"].to_s
      return nil unless content.include?(REPORT_MARKER)
      return nil if Approval.lookup(@root, content)

      unapproved_message("new_str", nil, content)
    end

    def report_product(parent)
      return nil unless parent.is_a?(Hash)

      id = (parent["data_source_id"] || parent["database_id"]).to_s.delete_prefix("collection://").delete("-")
      @products.find { |product| [product.data_source_id, product.database_id].include?(id) }
    end

    def unapproved_message(field, product, content)
      target = product ? "#{product.code.upcase} のレポート DB への" : "レポートページへの"
      message = "#{target}書き込みを止めた: #{field} が `bin/weekly-report render` で検証済みの本文と一致しない。" \
                "render が出力した .notion.md の中身を一字一句そのまま渡す（手で組んだ本文・検証後に書き換えた本文は書き込めない）。" \
                "内容を直したいときは入力 JSON を直して render をやり直す。"
      diff = product && Approval.first_difference(@root, content, product)
      return message unless diff

      "#{message}\n最後に承認した本文と最初に食い違う行（空行を除いて #{diff['line']} 行目）:\n" \
        "  承認済み: #{diff['expected'].inspect}\n  渡した本文: #{diff['actual'].inspect}"
    end
  end
end
