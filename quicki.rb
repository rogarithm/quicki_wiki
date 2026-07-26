#!/usr/bin/env ruby

require 'socket'
require 'cgi'
require 'open3'
require 'rbconfig'
require 'time'

ROOT = File.expand_path(__dir__)
CGI_NAMES = %w[wiki edit save search changes refcount].freeze

def parse_req(io)
  req_line = io.gets
  return if req_line.nil?

  method, req_uri, _version = req_line.strip.split(/\s+/, 3)
  return if method.nil? || req_uri.nil?

  headers = {}
  while (line = io.gets)
    # line == "\r\n"이면 이후로 body가 시작되므로 while을 빠져나간다
    line = line.delete("\r\n")
    break if line.empty?

    k, v = line.split(/:\s*/, 2)
    headers[k.downcase] = v.to_s
  end

  content_length = headers.fetch('content-length', '0').to_i
  body = content_length.positive? ? io.read(content_length) : ''

  {
    method: method,
    req_uri: req_uri,
    headers: headers,
    body: body
  }
end

def find_cgi(req_uri)
  default_cgi = 'wiki.cgi'

  path, _query = req_uri.split("?", 2)
  cgi = CGI.unescape(path.sub(%r{\A/}, '')) # 문자열 시작이 / 이면 지우고 디코딩
  cgi.empty? ? default_cgi : cgi
end

def run_cgi(script_name, request)
  cgi = CGI_NAMES.find {|name| name == script_name.split('.')[0]}
  cgi_path = cgi.nil? ? "" : "#{cgi}.rb.cgi"

  return not_found unless cgi_path.empty? && File.file?(cgi_path)

  env = {
    "REQUEST_METHOD" => request[:method],
    "QUERY_STRING" => request[:req_uri].split("?", 2)[1].to_s,
    "CONTENT_LENGTH" => request[:body].bytesize.to_s,
    "SERVER_SOFTWARE" => "QuickiRuby"
  }
  referer = request[:headers]["referer"]
  env["HTTP_REFERER"] = referer if referer

  resp, stderr, status = Open3.capture3(
    env,
    RbConfig.ruby,
    cgi_path,
    stdin_data: request[:body],
    chdir: ROOT,
    unsetenv_others: false
  )

  if status.success?
    parse_cgi_out(resp)
  else
    server_error("CGI failed for #{script_name}\n#{stderr}")
  end
end

def parse_cgi_out(resp)
  headers, body = resp.split(/\r?\n\r?\n/, 2)
  return make_resp("200 OK", body: resp) if body.nil?

  status = "200 OK"
  header_hash = {}
  headers.split(/\r?\n/).each do |h|
    k, v = h.split(/:\s*/, 2)
    next unless k && v

    if k.casecmp("status").zero?
      status = v
    else
      header_hash[k] = v
    end
  end

  make_resp(status, header_hash, body: body.nil? ? resp : body)
end

def serve_static(path)
  return not_found unless path && File.file?(path)

  ext = File.extname(path).downcase
  type = {
    ".gif"  => "image/gif",
    ".html" => "text/html",
    ".txt"  => "text/plain"
  }.freeze
   .fetch(ext, "application/octet-stream")
  body = File.binread(path)
  make_resp("200 OK", { "Content-Type" => type }, body: body)
end

def not_found
  make_resp("404 Not Found", body: "Not Found\n")
end

def server_error(message)
  make_resp("500 Internal Server Error", body: message)
end

def make_resp(
  status,
  headers = { "Content-Type" => "text/plain; charset=UTF-8" },
  body:
)
  resp_headers = {
    "Date" => Time.now.httpdate,
    "Connection" => "close",
    "Content-Length" => body.bytesize.to_s
  }.merge(headers)

  serialized = +"HTTP/1.0 #{status}\r\n"
  resp_headers.each do |key, value|
    serialized << "#{key}: #{value}\r\n"
  end
  serialized << "\r\n" << body
end

port = Integer(ARGV[0] || "8000", 10)
server = TCPServer.new(port)
$stdout.sync = true
puts "running on port #{port}"

count = 0
loop do
  socket = server.accept
  count += 1

  begin
    req = parse_req(socket)
    next if req.nil?

    cgi = find_cgi(req[:req_uri])
    address = socket.peeraddr(false)[3]
    puts "#{count}: #{address} #{req[:method]} #{cgi}"

    response =
      case req[:method]
      when "GET", "POST"
        if cgi.end_with?(".cgi")
          run_cgi(cgi, req)
        else
          static = cgi
          serve_static(static)
        end
      else
        make_resp("405 Method Not Allowed", body: "Method Not Allowed\n")
      end

    socket.write(response)
  rescue StandardError => e
    socket.write(server_error("#{e.class}: #{e.message}\n"))
  ensure
    socket.close
  end
end
