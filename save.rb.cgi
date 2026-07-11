#!/usr/bin/env ruby

$stdout.sync = true

MARK = "\263".b
LINK = /[A-Z][a-z0-9]+(?:[A-Z][a-z0-9]+)+/

page = ENV.fetch("QUERY_STRING", "")[/\A#{LINK}\z/]
raise "BadSaveName\n" unless page

input = STDIN.read(ENV.fetch("CONTENT_LENGTH", "0").to_i)
body = {}

input.split("&").each do |pair|
  key, value = pair.split("=", 2)
  key = key.to_s.gsub("+", " ").gsub(/%(..)/) { [Regexp.last_match(1).hex].pack("C") }
  value = value.to_s.gsub("+", " ").gsub(/%(..)/) { [Regexp.last_match(1).hex].pack("C") }
  body[key] = value
end

text = body.fetch("Text", "")
if text.include?("\n")
  text = text.delete("\r")
else
  text = text.tr("\r", "\n")
end

text = text.delete(MARK)

backlink_target = nil
text = text.gsub(/<<(#{LINK})\b/) do
  backlink_target = Regexp.last_match(1)
  backlink_target
end

if backlink_target
  File.open(File.join("pages", backlink_target), "a") do |file|
    file.write("\n----\n#{page}")
  end
end

mode = "w"
if body.fetch("mode", "") =~ /append/
  mode = "a"
  text = "\n----\n\n#{text}"
end

File.open(File.join("pages", page), mode) do |file|
  file.write(text)
end

load "./wiki.rb.cgi", true
