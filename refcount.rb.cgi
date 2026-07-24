#!/usr/bin/env ruby

$stdout.sync = true
print "Content-type: text/html; charset=UTF-8\n\n"

LINK = /[A-Z][a-z0-9]+(?:[A-Z][a-z0-9]+)+/

files = Dir.children("pages").select { |name| name.match?(/\A#{LINK}\z/) }
refs = Hash.new { |hash, key| hash[key] = [] }

files.each do |file|
  contents = File.binread(File.join("pages", file))
  targets = {}
  contents.scan(LINK) do
    targets[Regexp.last_match(0)] = file
  end
  targets.each_key do |target|
    refs[target] << file
  end
end

refcnt = {}
files.each do |file|
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

par = {}
par["summary"] = ""
par["title"] = "Page References"
par["page"] = "http:pagerefs.cgi"
par["body"] = body

template = File.binread("template.html")
template.gsub!(/\$(\w+)/) { par.fetch(Regexp.last_match(1), "") }
print template
