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
      end

      pat = target.gsub(/[+?.*()\[\]{}|\\]/) { |char| "\\#{char}" }
      regex = /\b\w*(#{pat})\w*\b/i

      target = target.gsub('"', "&quot;")

      hits = count_hits(regex)
      files = Dir.children("pages").select { |name| name.match?(LINK) }.sort
      body = gen_body(target, regex)

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

    def count_hits(regex)
      hits = 0
      files = Dir.children("pages").select { |name| name.match?(LINK) }.sort
      files.each do |file|
        contents = File.binread(File.join("pages", file))

        if regex.match(file) || regex.match(contents)
          hits += 1
        end
      end
      hits
    end

    def gen_body(target, regex)
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

      files = Dir.children("pages").select { |name| name.match?(LINK) }.sort
      files.each do |file|
        contents = File.binread(File.join("pages", file))

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

Quicki::Searcher.new.handle_req
