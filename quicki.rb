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
    set :public_folder, File.join(ROOT, "public")
    set :static, true
  end

  before do
    logger.info("#{request.request_method} #{request.path_info}?#{request.query_string}")
  end

  CGI_NAMES.each do |name|
    get "/#{name}.cgi" do
      handle("#{name}.cgi", request)
    end

    post "/#{name}.cgi" do
      handle("#{name}.cgi", request)
    end
  end

  get '/' do
    handle('wiki.cgi', request)
  end

  %w[put patch delete options trace connect].map(&:upcase) # verb는 꼭 대문자여야 한다
                      .each do |verb|
    route verb, '/*' do
      make_resp("405 Method Not Allowed", body: "Method Not Allowed\n")
    end
  end

  error StandardError do |x|
    e = env['sinatra.error']
    status 500
    content_type "text/plain;charset=UTF-8"
    body "#{e.class}: #{e.message}\n"
  end

  not_found do
    status 404
    content_type "text/plain;charset=UTF-8"
    body "Not Found\n"
  end

  # 원본 accept 루프를 대체하는 Rack 엔트리포인트.
  # method/cgi 판별, 로깅, 디스패치 로직은 원본 loop 내부와 동일하게 유지.
  def handle(cgi, request)
    req_body = parse_req(request)
    run_cgi(cgi, request, req_body)
  end

  # method, query, referer 등은 sinatra request에서 바로 꺼내 쓰므로, 요청 본문만 계산해 돌려준다.
  # sinatra는 라우트 실행 전에 params를 만들면서 폼 본문을 끝까지 읽으므로, 되감은 뒤 읽는다.
  def parse_req(request)
    req_body = request.body
    req_body&.rewind
    req_body&.read.to_s
  end

  def run_cgi(script_name, request, req_body)
    cgi = CGI_NAMES.find {|name| name == script_name.split('.')[0]}
    cgi_path = cgi.nil? ? "" : "#{cgi}.cgi"
    halt(
      404,
      { "Content-Type" => "text/plain;charset=UTF-8" },
      "Not Found\n"
    ) if !File.file?(cgi_path)

    env = {
      "REQUEST_METHOD" => request.request_method,
      "QUERY_STRING" => request.query_string,
      "CONTENT_LENGTH" => req_body.bytesize.to_s,
      "SERVER_SOFTWARE" => "QuickiRuby"
    }
    referer = request.referer
    env["HTTP_REFERER"] = referer if referer

    resp, stderr, status = Open3.capture3(
      env,
      RbConfig.ruby,
      cgi_path,
      stdin_data: req_body,
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

  def server_error(message)
    make_resp("500 Internal Server Error", body: message)
  end

  # 응답 상태, 헤더, 본문을 sinatra 헬퍼(Sinatra::Helpers의 status/headers/body)로
  # 현재 요청의 response 객체에 채운다.
  def make_resp(
    status_line,
    resp_headers = { "Content-Type" => "text/plain;charset=UTF-8" },
    body:
  )
    code = status_line.to_s.split(" ", 2).first.to_i
    status(code)
    headers(resp_headers)
    body(body) # 키워드 인자 body가 헬퍼 이름을 가리므로, 괄호를 붙여 메서드 호출로 해석되게 한다
  end
end
