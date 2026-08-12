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

        line, has_matching, rule, match = sub2html(line, has_matching)

        body << wrap_block_tags(codes, rule, match)

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

      inline_js_url = /\b(javascript):\S.*/
      line = line.gsub(inline_js_url) do |match| # match에 매칭된 값이 들어간다
        current_idx = index
        index += 1
        in_place_urls[current_idx] = match
        "#{MARK}#{current_idx}#{MARK}" # 이 값으로 치환한다
      end

      plain_url = /\b#{PROTOCOL.source}:[^\s<>\[\]"'()]*[^\s<>\[\]"'(),.?]/
      line = line.gsub(plain_url) do |match|
        current_idx = index
        index += 1
        in_place_urls[current_idx] = match
        "#{MARK}#{current_idx}#{MARK}"
      end

      [in_place_urls, line]
    end

    # 패턴 (예: /^(\*+)/)
    # 그 줄 자체를 어떻게 치환할지 (예: <li>)
    # 이 매칭이 여는 블록 태그 이름 (예: UL, 헤더류는 H2 등, 빈 줄은 없음)
    # 그 블록의 깊이를 매치 결과로부터 계산하는 방법
    BLOCK_RULES = [
      # pattern,   replace_rule,     block_tag,    depth_rule
      [/^\s*$/,    ->(_) { "<p>" }],
      [/^\s/,      ->(m) { m },      "PRE",        ->(_) { 1 }],
      [/^(\*+)/,   ->(_) { "<li>" }, "UL",         ->(mat) {mat[1].length}],
      [/^(\#+)/,   ->(_) { "<li>" }, "OL",         ->(mat) {mat[1].length}],
      [/^(\d+)\./, ->(_) { "<li>" }, "OL",         ->(_) { 1 }],
      [/^!!!!/,    ->(_) { "" },     "H4",         ->(_) { 1 }],
      [/^!!!/,     ->(_) { "" },     "H3",         ->(_) { 1 }],
      [/^!!/,      ->(_) { "" },     "H2",         ->(_) { 1 }],
      [/^\"\"/,    ->(_) { "" },     "BLOCKQUOTE", ->(_) { 1 }],
    ].concat(
      [
        [/^(:+)(.+?):( +)/,
        ->(m) { "<dt>#{m[2]}<dd>" },
        "DL",
        ->(mat) {mat[1].length}]
      ]
    )

    def sub2html(line, has_matching)
      rule, match = BLOCK_RULES.filter_map {|r|
        pat = r[0]
        mat = pat.match(line)
        mat ? [r, mat] : nil
      }.first

      if rule
        has_matching = true
        pat, re, _tag, _depth_rule = rule
        line = line.sub(pat) { re.call(Regexp.last_match) }
      end
      [line, has_matching, rule, match]
    end

    def wrap_block_tags(codes, rule, match)
      return "" unless rule

      _pat, _re, tag, depth_rule = rule
      emit_code(codes, tag, depth_rule.call(match))
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
