#!/usr/bin/env ruby

require "socket"
require "cgi"
require "open3"
require "rbconfig"
require "time"

ROOT = File.expand_path(__dir__)
SERVER_NAME = "QuickiRuby"
DEFAULT_SCRIPT = "wiki.cgi"
CGI_PATHS = {
  "wiki.cgi" => "wiki.rb.cgi",
  "edit.cgi" => "edit.rb.cgi",
  "save.cgi" => "save.rb.cgi",
  "search.cgi" => "search.rb.cgi",
  "changes.cgi" => "changes.rb.cgi",
  "refcount.cgi" => "refcount.rb.cgi"
}.freeze
MIME_TYPES = {
  ".gif" => "image/gif",
  ".html" => "text/html",
  ".txt" => "text/plain"
}.freeze

def log_request(count, client, method, raw_path)
  address = client.peeraddr(false)[3]
  puts "#{count}: #{address} #{method} #{raw_path}"
end

def read_request(io)
  request_line = io.gets
  return if request_line.nil?

  method, target, protocol = request_line.strip.split(/\s+/, 3)
  return if method.nil? || target.nil?

  headers = {}
  while (line = io.gets)
    line = line.delete("\r\n")
    break if line.empty?

    key, value = line.split(/:\s*/, 2)
    headers[key.downcase] = value.to_s
  end

  content_length = headers.fetch("content-length", "0").to_i
  body = content_length.positive? ? io.read(content_length) : ""

  {
    method: method,
    target: target,
    protocol: protocol || "HTTP/1.0",
    headers: headers,
    body: body
  }
end

def decode_target(target)
  path, query = target.split("?", 2)
  path = CGI.unescape(path.sub(%r{\A/}, ""))
  path = DEFAULT_SCRIPT if path.empty?
  [path, query]
end

def safe_path(path)
  return if path.include?("\0")

  expanded = File.expand_path(path, ROOT)
  return unless expanded.start_with?(ROOT + File::SEPARATOR) || expanded == ROOT

  expanded
end

def cgi_script_for(path)
  CGI_PATHS.fetch(path, path.end_with?(".rb.cgi") ? path : "")
end

def run_cgi(script_name, request)
  script_path = safe_path(cgi_script_for(script_name))
  return not_found unless script_path && File.file?(script_path)

  env = {
    "REQUEST_METHOD" => request[:method],
    "QUERY_STRING" => request[:target].split("?", 2)[1].to_s,
    "CONTENT_LENGTH" => request[:body].bytesize.to_s,
    "SERVER_SOFTWARE" => SERVER_NAME
  }
  referer = request[:headers]["referer"]
  env["HTTP_REFERER"] = referer if referer

  stdout, stderr, status = Open3.capture3(
    env,
    RbConfig.ruby,
    script_path,
    stdin_data: request[:body],
    chdir: ROOT,
    unsetenv_others: false
  )

  if status.success?
    normalize_cgi_response(stdout)
  else
    server_error("CGI failed for #{script_name}\n#{stderr}")
  end
end

def normalize_cgi_response(output)
  headers, body = output.split(/\r?\n\r?\n/, 2)
  return http_response("200 OK", { "Content-Type" => "text/html; charset=UTF-8" }, output) if body.nil?

  status = "200 OK"
  header_hash = {}

  headers.split(/\r?\n/).each do |line|
    key, value = line.split(/:\s*/, 2)
    next unless key && value

    if key.casecmp("status").zero?
      status = value
    else
      header_hash[key] = value
    end
  end

  http_response(status, header_hash, body)
end

def serve_static(path)
  file_path = safe_path(path)
  return not_found unless file_path && File.file?(file_path)

  ext = File.extname(file_path).downcase
  type = MIME_TYPES.fetch(ext, "application/octet-stream")
  body = File.binread(file_path)
  http_response("200 OK", { "Content-Type" => type }, body)
end

def not_found
  http_response("404 Not Found", { "Content-Type" => "text/plain; charset=UTF-8" }, "Not Found\n")
end

def method_not_allowed
  http_response("405 Method Not Allowed", { "Content-Type" => "text/plain; charset=UTF-8" }, "Method Not Allowed\n")
end

def server_error(message)
  http_response("500 Internal Server Error", { "Content-Type" => "text/plain; charset=UTF-8" }, message)
end

def http_response(status, headers, body)
  response_headers = {
    "Date" => Time.now.httpdate,
    "Connection" => "close",
    "Content-Length" => body.bytesize.to_s
  }.merge(headers)

  serialized = +"HTTP/1.0 #{status}\r\n"
  response_headers.each do |key, value|
    serialized << "#{key}: #{value}\r\n"
  end
  serialized << "\r\n"
  serialized << body
  serialized
end

port = Integer(ARGV[0] || "8000", 10)
server = TCPServer.new(port)
$stdout.sync = true
puts "running on port #{port}"

count = 0
loop do
  client = server.accept
  count += 1

  begin
    request = read_request(client)
    next if request.nil?

    path, = decode_target(request[:target])
    log_request(count, client, request[:method], path.empty? ? "/" : path)

    response =
      case request[:method]
      when "GET", "POST"
        if path.end_with?(".cgi")
          run_cgi(path, request)
        else
          serve_static(path)
        end
      else
        method_not_allowed
      end

    client.write(response)
  rescue StandardError => e
    client.write(server_error("#{e.class}: #{e.message}\n"))
  ensure
    client.close
  end
end
