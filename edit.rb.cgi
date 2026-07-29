#!/usr/bin/env ruby

module Quicki
  class Editor
    LINK = /[A-Z][a-z0-9]+(?:[A-Z][a-z0-9]+)+/
    MARK = "\263".b

    def handle_req
      page = ENV.fetch("QUERY_STRING", "")[LINK] || "WelcomeVisitors"
      input = STDIN.read(ENV.fetch("CONTENT_LENGTH", "0").to_i)
      page_path = File.join("pages", page)
      source = File.exist?(page_path) ? File.binread(page_path) : nil

      mode = input.match?(/append/)
      text = gen_body(source)

      par = {}
      if mode
        par["title"] = "Add comment to #{page}"
        text = ""
        mode = "append"
      else
        par["title"] = "Edit #{page}"
        mode = "edit"
      end

      par["page"] = page
      par["body"] = "\t<form method=post action=\"save.cgi?#{page}\">\n" \
        "\t<textarea name=Text rows=16 cols=60 wrap=virtual>#{text}</textarea>\n" \
        "\t<p><input type=\"submit\" value=\" Save \">\n" \
        "      <input type=\"hidden\" name=\"mode\" value=\"#{mode}\">\n" \
        "\t</form>\n"

      template = File.binread("template.html")
      template.gsub!(/\$(\w+)/) do
        m = Regexp.last_match(1) # $\w+(템플릿 내의 변수 패턴)에 매칭되는 결과 중 \w+만 저장
        par.fetch(m, "") # 결과 중 par에 저장된 값이 있으면 템플릿에 값을 채운다
      end

      $stdout.sync = true
      print "Content-type: text/html; charset=UTF-8\n\n"
      print template
    end

    def gen_body(source)
      unless source
        return ''
      end

      if source.include?(MARK)
        fields = source.split(MARK, -1)
        mapped = {}
        fields.each_slice(2) do |key, value|
          mapped[key] = value
        end
        source = mapped["text"].to_s
      end
      source.gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;")
    end
  end
end

if $PROGRAM_NAME == __FILE__
  Quicki::Editor.new.handle_req
end
