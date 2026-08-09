#!/usr/bin/env ruby

module Quicki
  class Browser
    MARK = "\uE000"
    LINK = /[A-Z][a-z0-9]+(?:[A-Z][a-z0-9]+)+/
    PROTOCOL = /(?:http|ftp|mailto|file|gopher|telnet|news)/
    MONTHS = %w[January February March April May June July August September October November December]

    def handle_req
      $stdout.sync = true
      print "Content-type: text/html; charset=UTF-8\n\n"

      page = ENV.fetch("QUERY_STRING", "")[/\A(#{LINK})\z/, 1] || "WelcomeVisitors"

      par = {}
      par["page"] = page
      par["title"] = page.gsub(/(.)([A-Z])/, '\1 \2')

      date = nil
      page_path = File.join("pages", page)
      if File.exist?(page_path)
        source = File.binread(page_path).force_encoding("UTF-8")

        body = render_wiki_doc(source.to_s)
        time = File.mtime(page_path)
        date = "#{MONTHS[time.month - 1]} #{time.day}, #{time.year}"
      else
        body = "  \"#{page}\" does not yet exist. <BR>\n" \
          "  Use the <strong>Edit</strong> button to create it.\n"
      end

      par["summary"] = " -- Last edited #{date}" if date
      par["body"] = body
      par["action"] = " <form method=post action=\"edit.cgi?#{page}\">\n" \
        " <input type=submit value=\" Edit \">\n" \
        " </form>\n"

      template = File.binread("template.html")
      template.gsub!(/\$(\w+)/) { par.fetch(Regexp.last_match(1), "") }
      print template
    end

    def render_wiki_doc(source)
      codes = []
      in_place_urls = []
      body = +""
      escaped = source.gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;")

      escaped.split(/\n/).each do |line|
        in_place_urls, line = extract_in_place_urls(in_place_urls, line)

        has_matching = false
        line.sub!(/^\t+/, "")

        line, has_matching, rule_n_match = sub2html(line, has_matching)

        body << wrap_block_tags(codes, rule_n_match)

        # 블록 규칙에 매칭되지 않는 경우, 열린 블록을 모두 닫는다
        body << emit_code(codes, "", 0) unless has_matching

        line.sub!(/^-----*/, "<hr>")
        line.gsub!(/'''(.*?)'''/, '<strong>\1</strong>')
        line.gsub!(/''(.*?)''/, '<em>\1</em>')
        line.gsub!(/\[Search\]/, "<form action=search.cgi><input type=text name=search size=40>\n   <input type=\"submit\" value=\"Search\"></form>")
        line.gsub!(LINK) { |match| as_anchor(match) }
        marker_pattern = Regexp.new("#{Regexp.escape(MARK)}(\\d+)#{Regexp.escape(MARK)}")
        line.gsub!(marker_pattern) { in_place_url(in_place_urls, Regexp.last_match(1).to_i) }

        body << line << "\n"
      end

      body << emit_code(codes, "", 0)
      body
    end

    def extract_in_place_urls(in_place_urls, line)
      index = 0

      while line.sub!(/\b(javascript):\S.*/, "#{MARK}#{index}#{MARK}")
        in_place_urls[index] = Regexp.last_match(0)
        index += 1
      end

      while line.sub!(/\b#{PROTOCOL.source}:[^\s<>\[\]"'()]*[^\s<>\[\]"'(),.?]/, "#{MARK}#{index}#{MARK}")
        in_place_urls[index] = Regexp.last_match(0)
        index += 1
      end

      [in_place_urls, line]
    end

    def sub2html(line, has_matching)
      rules = [
        # pattern, replace
        [/^\s*$/, "<p>"],
        # match만 하고 치환은 하지 않는다.
        # emit_code 연산 시 이 rules에 포함된 패턴만 체크하기 때문에,
        # emit_code용 rule을 현재 rule이 모두 포함해야 한다
        [/^\s/, nil],
        [/^(\*+)/, "<li>"],
        [/^(\#+)/, "<li>"],
        [/^(:+)(.+?):( +)/, ->(m) { "<dt>#{m[2]}<dd>" }],
        [/^(\d+)\./, "<li>"],
        [/^!!!!/, ""],
        [/^!!!/, ""],
        [/^!!/, ""],
        [/^\"\"/, ""],
      ]

      rule_n_match = rules.filter_map {|r|
        pat = r[0]
        mat = pat.match(line)
        mat ? [r, mat].flatten! : nil
      }.first

      if rule_n_match
        has_matching = true
        pat, re, _ = rule_n_match
        line = if re.nil? # 치환하면 안되는 경우는 여기서 처리한다
                 line
               elsif re.respond_to?(:call)
                 line.sub(pat) { re.call(Regexp.last_match) }
               else
                 line.sub(pat, re)
               end
      end
      [line, has_matching, rule_n_match]
    end

    def wrap_block_tags(codes, rule_n_match)
      rules = [
        # pattern, code, depth
        [/^\s/, "PRE", 1],
        [/^(\*+)/, "UL", ->(mat) {mat[1].length}],
        [/^(\#+)/, "OL", ->(mat) {mat[1].length}],
        [/^(:+)(.+?):( +)/, "DL", ->(mat) {mat[1].length}],
        [/^(\d+)\./, "OL", 1],
        [/^!!!!/, "H4", 1],
        [/^!!!/, "H3", 1],
        [/^!!/, "H2", 1],
        [/^\"\"/, "BLOCKQUOTE", 1],
      ]
      return "" unless rule_n_match

      pat, _, mat = rule_n_match
      r = rules.find {|r| r[0] == pat}
      return "" unless r

      _, code, depth = r
      if depth.respond_to?(:call)
        emit_code(codes, code, depth.call(mat))
      else
        emit_code(codes, code, depth)
      end
    end

    def emit_code(codes, code, depth)
      tags = +""
      while codes.length > depth
        tags << "</#{codes[-1]}>\n<p>"
        codes.pop
      end
      while codes.length < depth
        tags << "<#{code}>"
        codes << code
      end
      if codes[-1].to_s != code
        tags << "</#{codes[-1]}>\n<#{code}>"
        codes[-1] = code
      end
      tags
    end

    def as_anchor(title)
      if File.exist?(File.join("pages", title))
        "<a href=wiki.cgi?#{title}>#{title}</a>"
      else
        "<a href=edit.cgi?#{title}>?</a>#{title}"
      end
    end

    def in_place_url(in_place_urls, index)
      ref = in_place_urls[index].sub(/^(javascript.{30}).*/, '\1 ...')
      if ref.match?(/\.(gif|jpeg|jpg|png)\z/i)
        "<img src=\"#{ref}\">"
      else
        "<a href=\"#{in_place_urls[index]}\">#{ref}</a>"
      end
    end
  end
end

if $PROGRAM_NAME == __FILE__
  Quicki::Browser.new.handle_req
end
