#!/usr/bin/env ruby

$stdout.sync = true
print "Content-type: text/html\n\n"

LINK = /\A[A-Z][a-z0-9]+(?:[A-Z][a-z0-9]+)+\z/

target = ENV.fetch("QUERY_STRING", "")[/search=([^&]*)/, 1].to_s
target = target.gsub("+", " ").gsub(/%(..)/) { [Regexp.last_match(1).hex].pack("C") }

pat = target.gsub(/[+?.*()\[\]{}|\\]/) { |char| "\\#{char}" }
regex = Regexp.new("\\b\\w*(#{pat})\\w*\\b", Regexp::IGNORECASE)

target = target.gsub('"', "&quot;")
body = " <form action=search.cgi>\n" \
  "  <input\n" \
  "   type=\"text\"\n" \
  "   size=\"40\"\n" \
  "   name=\"search\"\n" \
  "   value=\"#{target}\">\n" \
  "  <input type=\"submit\" value=\"Search\">\n" \
  " </form>\n"

files = Dir.children("pages").select { |name| name.match?(LINK) }.sort

hits = 0
files.each do |file|
  contents = File.binread(File.join("pages", file))
  match = nil

  if (match_data = regex.match(file))
    match = match_data[0]
  elsif (match_data = regex.match(contents))
    match = match_data[0]
  end

  next unless match

  hits += 1
  body << "<a href=wiki.cgi?#{file}>#{file}</a> . . . . . .  #{match}<br>\n"
end

par = {}
par["summary"] = "#{hits.zero? ? 'No' : hits} pages found out of #{files.length} pages searched."
par["title"] = "Search Results"
par["page"] = "WelcomeVisitors"
par["body"] = body

template = File.binread("template.html")
template.gsub!(/\$(\w+)/) { par.fetch(Regexp.last_match(1), "") }
print template
