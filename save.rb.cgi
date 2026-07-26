#!/usr/bin/env ruby

module Quicki
  class Writer
    MARK = "\263".b
    LINK = /[A-Z][a-z0-9]+(?:[A-Z][a-z0-9]+)+/

    def handle_req
      page = ENV.fetch("QUERY_STRING", "")[/\A#{LINK}\z/]
      raise "BadSaveName\n" unless page

      input = STDIN.read(ENV.fetch("CONTENT_LENGTH", "0").to_i)
      body = gen_body(input)

      text = body.fetch("Text", "")
      text = if text.include?("\n")
               text.delete("\r")
             else
               text.tr("\r", "\n")
             end

      text = text.delete(MARK)

      # <<WikiWord 형식이 있으면 WikiWord 페이지에 현재 페이지 백링크를 추가한다
      backlink_target = nil
      text = text.gsub(/<<(#{LINK})\b/) do
        backlink_target = Regexp.last_match(1) # <<를 제외한 LINK 형식 문자열
        backlink_target
      end

      $stdout.sync = true
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
    end

    def gen_body(input)
      body = {}
      input.split("&").each do |pair|
        key, value = pair.split("=", 2)
        key = key.to_s
                 .gsub("+", " ") # form 인코딩에서 +로 표현하는 공백을 되돌린다
                 .gsub(/%(..)/) do
          m = Regexp.last_match(1)
          [m.hex].pack("C") # %HH 형태의 percent-encoding을 바이트로 되돌린다
        end
        value = value.to_s
                     .gsub("+", " ") # form 인코딩에서 +로 표현하는 공백을 되돌린다
                     .gsub(/%(..)/) do
          m = Regexp.last_match(1)
          [m.hex].pack("C") # %HH 형태의 percent-encoding을 바이트로 되돌린다
        end
        body[key] = value
      end
      body
    end
  end
end

Quicki::Writer.new.handle_req
