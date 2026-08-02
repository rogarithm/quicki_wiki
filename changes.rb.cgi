#!/usr/bin/env ruby

module Quicki
  class ChangeViewer
    LINK = /\A[A-Z][a-z0-9]+(?:[A-Z][a-z0-9]+)+\z/
    MONTHS = %w[January February March April May June July August September October November December]

    def handle_req
      # 최근 날짜가 앞에 오도록 파일을 정렬한다
      dated_pages = Dir.children("pages")
                       .select { |name| name.match?(LINK) }
                       .map { |name| [File.mtime(File.join("pages", name)), name] }
                       .sort_by(&:first)
                       .reverse

      # 최대로 보여 줄 파일 갯수
      max = ENV.fetch("QUERY_STRING", "")[/\bmax=(\d+)/, 1]
      max = max ? max.to_i : 25

      par = {}
      par["body"] = gen_body(dated_pages, max)
      par["title"] = "Recent Changes"
      par["page"] = "http:changes.cgi"

      template = File.binread("template.html")
      template.gsub!(/\$(\w+)/) do
        m = Regexp.last_match(1) # $\w+(템플릿 내의 변수 패턴)에 매칭되는 결과 중 \w+만 저장
        par.fetch(m, "") # 결과 중 par에 저장된 값이 있으면 템플릿에 값을 채운다
      end

      $stdout.sync = true
      print "Content-type: text/html; charset=UTF-8\n\n"
      print template
    end

    def gen_body(dated_pages, max)
      body = "<dl>\n"
      last_date = nil
      dated_pages.each do |time, file|
        date = "#{MONTHS[time.month - 1]} #{time.day}, #{time.year}"
        if date != last_date
          body << "<dt>"
          body << "<br>" unless last_date.nil? # 처음을 제외하고 항상 붙인다
          body << date
          last_date = date
        end
        body << "<dd><a href=wiki.cgi?#{file}>#{file}</a>\n"
        max -= 1
        break if max.zero?
      end
      body << "</dl>\n"
    end
  end
end

if $PROGRAM_NAME == __FILE__
  Quicki::ChangeViewer.new.handle_req
end
