#!/usr/bin/env ruby

$stdout.sync = true
print "Content-type: text/html; charset=UTF-8\n\n"

MARK = "\263".b
LINK = /[A-Z][a-z0-9]+(?:[A-Z][a-z0-9]+)+/
PROTOCOL = /(?:http|ftp|mailto|file|gopher|telnet|news)/
MONTHS = %w[January February March April May June July August September October November December]

def format_body(source)
  @code = []
  body = +""
  escaped = source.gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;")

  escaped.split(/\n/).each do |line|
    index = 0
    @in_place_urls = []

    while line.sub!(/\b(javascript):\S.*/, "#{MARK}#{index}#{MARK}")
      @in_place_urls[index] = Regexp.last_match(0)
      index += 1
    end

    while line.sub!(/\b#{PROTOCOL.source}:[^\s<>\[\]"'()]*[^\s<>\[\]"'(),.?]/, "#{MARK}#{index}#{MARK}")
      @in_place_urls[index] = Regexp.last_match(0)
      index += 1
    end

    code = ""
    line.sub!(/^\t+/, "")
    if line.sub!(/^\s*$/, "<p>")
      code = "..."
    end
    if line.match?(/^\s/)
      body << emit_code("PRE", 1)
      code = "PRE"
    end
    if line.sub!(/^(\*+)/, "<li>")
      body << emit_code("UL", Regexp.last_match(1).length)
      code = "UL"
    end
    if line.sub!(/^(\#+)/, "<li>")
      body << emit_code("OL", Regexp.last_match(1).length)
      code = "OL"
    end
    if line.sub!(/^(:+)(.+?):( +)/) { "<dt>#{$2}<dd>" }
      body << emit_code("DL", Regexp.last_match(1).length)
      code = "DL"
    end
    if line.sub!(/^(\d+)\./, "<li>")
      body << emit_code("OL", 1)
      code = "OL"
    end
    if line.sub!(/^!!!!/, "")
      body << emit_code("H4", 1)
      code = "H4"
    end
    if line.sub!(/^!!!/, "")
      body << emit_code("H3", 1)
      code = "H3"
    end
    if line.sub!(/^!!/, "")
      body << emit_code("H2", 1)
      code = "H2"
    end
    if line.sub!(/^\"\"/, "")
      body << emit_code("BLOCKQUOTE", 1)
      code = "BLOCKQUOTE"
    end

    body << emit_code("", 0) if code.empty?

    line.sub!(/^-----*/, "<hr>")
    line.gsub!(/'''(.*?)'''/, '<strong>\1</strong>')
    line.gsub!(/''(.*?)''/, '<em>\1</em>')
    line.gsub!(/\[Search\]/, "<form action=search.cgi><input type=text name=search size=40>\n   <input type=\"submit\" value=\"Search\"></form>")
    line.gsub!(LINK) { |match| as_anchor(match) }
    marker_pattern = Regexp.new("#{Regexp.escape(MARK)}(\\d+)#{Regexp.escape(MARK)}".b)
    line.gsub!(marker_pattern) { in_place_url(Regexp.last_match(1).to_i) }

    body << line << "\n"
  end

  body << emit_code("", 0)
  body
end

def emit_code(code, depth)
  tags = +""
  while @code.length > depth
    tags << "</#{@code.pop}>\n<p>"
  end
  while @code.length < depth
    @code << code
    tags << "<#{code}>"
  end
  if @code.last.to_s != code
    tags << "</#{@code.last}>\n<#{code}>"
    @code[-1] = code
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

def in_place_url(index)
  ref = @in_place_urls[index].sub(/^(javascript.{30}).*/, '\1 ...')
  if ref.match?(/\.(gif|jpeg|jpg|png)\z/i)
    "<img src=\"#{ref}\">"
  else
    "<a href=\"#{@in_place_urls[index]}\">#{ref}</a>"
  end
end

def mdy(time)
  "#{MONTHS[time.month - 1]} #{time.day}, #{time.year}"
end

@code = []
@in_place_urls = []

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
