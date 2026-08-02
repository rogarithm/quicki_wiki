#!/usr/bin/env ruby

# 각 위키 페이지를 참조하는 다른 위키 페이지 수를 집계한다
module Quicki
  class BacklinkCounter
    LINK = /[A-Z][a-z0-9]+(?:[A-Z][a-z0-9]+)+/

    def handle_req
      files = Dir.children("pages").select { |name| name.match?(/\A#{LINK}\z/) }
      # 파일명=>파일 내용 형식의 해시를 만든다
      pages = load_pages(files)

      par = {}
      par["summary"] = ""
      par["title"] = "Page References"
      par["page"] = "http:pagerefs.cgi"
      par["body"] = gen_body(pages)

      template = File.binread("template.html")
      template.gsub!(/\$(\w+)/) do
        m = Regexp.last_match(1) # $\w+(템플릿 내의 변수 패턴)에 매칭되는 결과 중 \w+만 저장
        par.fetch(m, "") # 결과 중 par에 저장된 값이 있으면 템플릿에 값을 채운다
      end

      $stdout.sync = true
      print "Content-type: text/html; charset=UTF-8\n\n"
      print template
    end

    def load_pages(files)
      files.to_h { |file| [file, File.binread(File.join("pages", file))] }
    end

    def gen_body(pages)
      files = pages.keys
      refs = Hash.new do |hash, key| # hash는 refs 자신
        hash[key] = [] # hash[key] 데이터가 없을 경우 기본값을 설정한다
      end

      files.each do |file|
        contents = pages[file]
        targets = {}
        contents.scan(LINK) do |mat_link|
          # mat_link 페이지를 file 위키 페이지에서 참조하고 있음을 중복되지 않게 기록한다
          targets[mat_link] = file
        end
        targets.each_key do |target|
          # target 페이지를 참조하고 있는 위키 페이지 목록에 file 위키 페이지를 추가한다
          refs[target] << file
        end
      end

      refcnt = {}
      files.each do |file|
        # file 위키 페이지를 참조한 다른 위키 페이지 수를 기록한다
        refcnt[file] = refs[file].length
      end

      files = files.sort_by { |file| [-refcnt[file], file] }

      body = "<table border=0 cellspacing=0 cellpadding=0>\n"
      files.each do |file|
        body << "<tr>"
        body << "<td valign=right>#{refcnt[file]}</td>"
        body << "<td>&nbsp;&nbsp;<a href=wiki.cgi?#{file}>#{file}</a></td>"
        body << "</tr>\n"
      end
      body << "</table>\n"
      body
    end
  end
end

if $PROGRAM_NAME == __FILE__
  Quicki::BacklinkCounter.new.handle_req
end
