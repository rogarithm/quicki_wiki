#!/usr/bin/env ruby

$stdout.sync = true
print "Content-type: text/html\n\n"

def mdy(time)
  "#{MONTHS[time.month - 1]} #{time.day}, #{time.year}"
end

LINK = /\A[A-Z][a-z0-9]+(?:[A-Z][a-z0-9]+)+\z/
MONTHS = %w[January February March April May June July August September October November December]

dated_pages = Dir.children("pages")
  .select { |name| name.match?(LINK) }
  .map { |name| [File.mtime(File.join("pages", name)), name] }
  .sort_by(&:first)
  .reverse

max = ENV.fetch("QUERY_STRING", "")[/\bmax=(\d+)/, 1]
max = max ? max.to_i : 25

body = "<dl>\n"
last_date = nil

dated_pages.each do |time, file|
  date = mdy(time)
  if date != last_date
    body << "<dt>"
    body << "<br>" unless last_date.nil?
    body << date
    last_date = date
  end
  body << "<dd><a href=wiki.cgi?#{file}>#{file}</a>\n"
  max -= 1
  break if max.zero?
end
body << "</dl>\n"

par = {}
par["body"] = body
par["title"] = "Recent Changes"
par["page"] = "http:changes.cgi"

template = File.binread("template.html")
template.gsub!(/\$(\w+)/) { par.fetch(Regexp.last_match(1), "") }
print template
