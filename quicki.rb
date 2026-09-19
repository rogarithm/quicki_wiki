#!/usr/bin/env ruby

require 'sinatra/base'
require 'cgi'
require 'open3'
require 'rbconfig'

class QuickiApp < Sinatra::Base
  ROOT = File.expand_path(__dir__)
  CGI_NAMES = %w[wiki edit save search changes refcount].freeze

  configure do
    enable :logging
  end

  before do
    logger.info("#{request.request_method} #{request.path_info}?#{request.query_string}")
  end

  get '/*' do
    handle(request)
  end

  post '/*' do
    handle(request)
  end

  %w[put patch delete options trace connect].map(&:upcase) # verb는 꼭 대문자여야 한다
                      .each do |verb|
    route verb, '/*' do
      make_resp("405 Method Not Allowed", body: "Method Not Allowed\n")
    end
  end

  # 원본 accept 루프를 대체하는 Rack 엔트리포인트.
  # method/cgi 판별, 로깅, 디스패치 로직은 원본 loop 내부와 동일하게 유지.
  def handle(request)
    req = parse_req(request)
    cgi = find_cgi(req[:req_uri])

    cgi.end_with?(".cgi") ? run_cgi(cgi, req) : serve_static(cgi)
  rescue StandardError => e
    server_error("#{e.class}: #{e.message}\n")
  end

  # 기존 parse_req(소켓에서 직접 읽던 부분)를 Rack env 기반으로 대체.
  # 반환 형태는 원본 parse_req와 동일하게 맞춰서 이후 로직을 그대로 재사용한다.
  def parse_req(request)
    query = request.query_string
    req_uri = request.path_info
    req_uri += "?#{query}" unless query.empty?

    {
      method: request.request_method,
      req_uri: req_uri,
      headers: {"referer" => request.referer}.compact,
      body: request.body&.read.to_s
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
    cgi_path = cgi.nil? ? "" : "#{cgi}.cgi"

    return not_found if cgi_path.empty? || !File.file?(cgi_path)

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

  # 원본은 raw HTTP 텍스트("HTTP/1.0 ...")를 문자열로 조립했지만,
  # Puma/Rack은 [status:Integer, headers:Hash, body:Enumerable] 3-tuple을 요구하므로
  # 여기서만 조립 방식을 바꾼다. status/header 병합 로직 자체는 원본과 동일.
  def make_resp(
    status,
    headers = { "Content-Type" => "text/plain; charset=UTF-8" },
    body:
  )
    resp_headers = {
      "Content-Length" => body.bytesize.to_s
    }.merge(headers)

    code = status.to_s.split(" ", 2).first.to_i
    [code, resp_headers, [body]]
  end
end
