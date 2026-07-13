#!/usr/bin/env ruby

$stdout.sync = true
print "Content-type: text/html; charset=UTF-8\n\n"

MARK = "\263".b
LINK = /[A-Z][a-z0-9]+(?:[A-Z][a-z0-9]+)+/
PROTOCOL = /(?:http|ftp|mailto|file|gopher|telnet|news)/
MONTHS = %w[January February March April May June July August September October November December]

module Quicki
  class Browser
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
  end
end

def format_body(source)
  codes = []
  in_place_urls = []
  body = +""
  escaped = source.gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;")

  escaped.split(/\n/).each do |line|
    in_place_urls, line = Quicki::Browser.new.extract_in_place_urls(in_place_urls, line)

    code = ""
    line.sub!(/^\t+/, "")
    if line.sub!(/^\s*$/, "<p>")
      code = "..."
    end
    if line.match?(/^\s/)
      body << emit_code(codes, "PRE", 1)
      code = "PRE"
    end
    if line.sub!(/^(\*+)/, "<li>")
      body << emit_code(codes, "UL", Regexp.last_match(1).length)
      code = "UL"
    end
    if line.sub!(/^(\#+)/, "<li>")
      body << emit_code(codes, "OL", Regexp.last_match(1).length)
      code = "OL"
    end
    if line.sub!(/^(:+)(.+?):( +)/) { "<dt>#{$2}<dd>" }
      body << emit_code(codes, "DL", Regexp.last_match(1).length)
      code = "DL"
    end
    if line.sub!(/^(\d+)\./, "<li>")
      body << emit_code(codes, "OL", 1)
      code = "OL"
    end
    if line.sub!(/^!!!!/, "")
      body << emit_code(codes, "H4", 1)
      code = "H4"
    end
    if line.sub!(/^!!!/, "")
      body << emit_code(codes, "H3", 1)
      code = "H3"
    end
    if line.sub!(/^!!/, "")
      body << emit_code(codes, "H2", 1)
      code = "H2"
    end
    if line.sub!(/^\"\"/, "")
      body << emit_code(codes, "BLOCKQUOTE", 1)
      code = "BLOCKQUOTE"
    end

    body << emit_code(codes, "", 0) if code.empty?

    line.sub!(/^-----*/, "<hr>")
    line.gsub!(/'''(.*?)'''/, '<strong>\1</strong>')
    line.gsub!(/''(.*?)''/, '<em>\1</em>')
    line.gsub!(/\[Search\]/, "<form action=search.cgi><input type=text name=search size=40>\n   <input type=\"submit\" value=\"Search\"></form>")
    line.gsub!(LINK) { |match| as_anchor(match) }
    marker_pattern = Regexp.new("#{Regexp.escape(MARK)}(\\d+)#{Regexp.escape(MARK)}".b)
    line.gsub!(marker_pattern) { in_place_url(in_place_urls, Regexp.last_match(1).to_i) }

    body << line << "\n"
  end

  body << emit_code(codes, "", 0)
  body
end

def emit_code(codes, code, depth)
  tags = +""
  while codes.length > depth
    tags << "</#{codes.pop}>\n<p>"
  end
  while codes.length < depth
    codes << code
    tags << "<#{code}>"
  end
  if codes.last.to_s != code
    tags << "</#{codes.last}>\n<#{code}>"
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

def mdy(time)
  "#{MONTHS[time.month - 1]} #{time.day}, #{time.year}"
end

page = ENV.fetch("QUERY_STRING", "")[/\A(#{LINK})\z/, 1] || "WelcomeVisitors"

par = {}
par["page"] = page
par["title"] = page.gsub(/(.)([A-Z])/, '\1 \2')

body = nil
date = nil

page_path = File.join("pages", page)
if File.exist?(page_path)
  source = File.binread(page_path)
  if source.include?(MARK)
    fields = source.split(MARK, -1)
    mapped = {}
    fields.each_slice(2) do |key, value|
      mapped[key] = value
    end
    source = mapped["text"]
  end

  body = format_body(source.to_s)
  date = mdy(File.mtime(page_path))
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
