#!/usr/bin/env ruby

$stdout.sync = true
print "Content-type: text/html; charset=UTF-8\n\n"

LINK = /[A-Z][a-z0-9]+(?:[A-Z][a-z0-9]+)+/
MARK = "\263".b

page = ENV.fetch("QUERY_STRING", "")[LINK] || "WelcomeVisitors"

input = STDIN.read(ENV.fetch("CONTENT_LENGTH", "0").to_i)

mode = input.match?(/append/)
text = +""

page_path = File.join("pages", page)
if File.exist?(page_path)
  source = File.binread(page_path)
  if source.include?(MARK)
    fields = source.split(MARK, -1)
    mapped = {}
    fields.each_slice(2) do |key, value|
      mapped[key] = value
    end
    source = mapped["text"].to_s
  end
  text = source.gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;")
end

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
template.gsub!(/\$(\w+)/) { par.fetch(Regexp.last_match(1), "") }
print template
