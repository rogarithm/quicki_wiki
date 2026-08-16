#!/usr/bin/env ruby

module Quicki
  class Searcher
    LINK = /\A[A-Z][a-z0-9]+(?:[A-Z][a-z0-9]+)+\z/

    def handle_req
      target = ENV.fetch("QUERY_STRING", "")[/search=([^&]*)/, 1] # [] 두번째 인자인 1은 ()로 캡쳐한 값만 가져온다
                 .to_s
      target = target.gsub("+", " ").gsub(/%(..)/) do
        m = Regexp.last_match(1)
        [m.hex].pack("C")
      end.force_encoding("UTF-8")

      pat = target.gsub(/[+?.*()\[\]{}|\\]/) { |char| "\\#{char}" }
      regex = /\b\w*(#{pat})\w*\b/i

      target = target.gsub('"', "&quot;")

      files = Dir.children("pages").select { |name| name.match?(LINK) }.sort
      pages = files.to_h { |file| [file, File.binread(File.join("pages", file)).force_encoding("UTF-8")] }
      hits = count_hits(regex, pages)
      body = gen_body(target, regex, pages)

      par = {}
      par["summary"] = "#{hits.zero? ? 'No' : hits} pages found out of #{files.length} pages searched."
      par["title"] = "Search Results"
      par["page"] = "WelcomeVisitors"
      par["body"] = body

      template = File.binread("template.html")
      template.gsub!(/\$(\w+)/) { par.fetch(Regexp.last_match(1), "") }

      $stdout.sync = true
      print "Content-type: text/html; charset=UTF-8\n\n"
      print template
    end

    def count_hits(regex, pages)
      hits = 0
      pages.each do |file, contents|
        if regex.match(file) || regex.match(contents)
          hits += 1
        end
      end
      hits
    end

    def gen_body(target, regex, pages)
      body = <<-FORM
 <form action=search.cgi>
  <input
   type="text"
   size="40"
   name="search"
   value="#{target}">
  <input type="submit" value="Search">
 </form>
FORM

      pages.each do |file, contents|
        match = nil
        if (match_data = regex.match(file))
          match = match_data[0]
        elsif (match_data = regex.match(contents))
          match = match_data[0]
        end

        next unless match

        body << "<a href=wiki.cgi?#{file}>#{file}</a> . . . . . .  #{match}<br>\n"
      end
      body
    end
  end
end

if $PROGRAM_NAME == __FILE__
  Quicki::Searcher.new.handle_req
end
