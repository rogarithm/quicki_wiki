require_relative "test_helper"

class QuickiCoreTest < Minitest::Test
  def setup
    @qa = QuickiApp.new!
  end

  # 다음 시나리오는 이제 QuickiApp의 책임이 아니라 Puma/Rack이 보장한다:
  # - 요청 라인이 없거나 불완전한 경우 (puma에서 유효한 요청 라인을 보장)
  # - 빈 줄을 만나면 헤더 파싱을 멈추고 이후를 body로 처리 (rack에서 처리)
  # - 요청 라인에 method 또는 req_uri가 없는 경우 처리 (rack에서 처리)

  # GET 요청으로 받은 env로부터 method, req_uri, headers, 빈 body를 올바르게 파싱한다
  def test_parse_req_parses_get_request
    env = Rack::MockRequest.env_for(
      "/wiki.cgi?Foo",
      method: "GET",
      "HTTP_REFERER" => "here"
    )
    req = Rack::Request.new(env)

    parsed_req = @qa.parse_req(req)

    assert_equal("GET", parsed_req[:method])
    assert_equal("/wiki.cgi?Foo", parsed_req[:req_uri])
    assert_equal("here", parsed_req[:headers]["referer"])
    assert_equal("", parsed_req[:body])
  end

  # POST 요청의 body는 rack.input에 담긴다
  def test_parse_req_reads_post_body
    env = Rack::MockRequest.env_for(
      "/save.cgi?Page",
      method: "POST",
      input: "abc=123"
    )
    req = Rack::Request.new(env)

    parsed_req = @qa.parse_req(req)

    assert_equal("abc=123", parsed_req[:body])
  end

  # 허용 목록에 없는 CGI 이름이거나 매핑된 .cgi 파일이 실제로 없으면 not_found를 반환한다
  def test_run_cgi_returns_not_found_for_unknown_or_missing_script
    request = {method: "GET", req_uri: "/", headers: {}, body: ""}
    response = @qa.run_cgi("unknown.cgi", request)
    assert_equal(404, response[0])
    assert_equal(["Not Found\n"], response[2])

    File.stub(:file?, false) do
      request = {method: "GET", req_uri: "/", headers: {}, body: ""}
      response = @qa.run_cgi("wiki.cgi", request)
      assert_equal(404, response[0])
      assert_equal(["Not Found\n"], response[2])
    end
  end

  # REQUEST_METHOD, QUERY_STRING, CONTENT_LENGTH, SERVER_SOFTWARE를 CGI 실행 환경으로 전달한다
  def test_run_cgi_passes_expected_environment
    request = {
      method: "POST",
      req_uri: "/save.cgi?PageName",
      headers: {"referer" => "http://example.test/from"},
      body: "abc=123"
    }
    captured_env = nil
    Open3.stub(:capture3, lambda { |env, *_args, **kwargs|
      captured_env = env.merge("stdin" => kwargs[:stdin_data], "chdir" => kwargs[:chdir])
      ["Status: 201 Created\nX-Test: yes\n\nok", "", status_double(true)]
    }) do
      response = @qa.run_cgi("save.cgi", request)

      assert_equal(201, response[0])
    end

    assert_equal("POST", captured_env["REQUEST_METHOD"])
    assert_equal("PageName", captured_env["QUERY_STRING"])
    assert_equal("7", captured_env["CONTENT_LENGTH"])
    assert_equal("QuickiRuby", captured_env["SERVER_SOFTWARE"])
    assert_equal("http://example.test/from", captured_env["HTTP_REFERER"])
    assert_equal("abc=123", captured_env["stdin"])
    assert_equal(TEST_ROOT, captured_env["chdir"])
  end

  # CGI 실행이 성공하면 parse_cgi_out으로 응답을 해석한다
  def test_run_cgi_parses_successful_output
    File.stub(:file?, true) do
      Open3.stub(:capture3, ["Status: 202 Accepted\nX-Test: yes\n\nbody", "", status_double(true)]) do
        request = {method: "GET", req_uri: "/wiki.cgi?Foo", headers: {}, body: ""}
        response = @qa.run_cgi("wiki.cgi", request)

        assert_equal(202, response[0])
        assert_equal(true, response[1].has_key?("X-Test"))
        assert_equal(["body"], response[2])
      end
    end
  end

  # CGI 실행이 실패하면 stderr 내용을 포함한 server_error를 반환한다
  def test_run_cgi_returns_server_error_when_cgi_fails
    File.stub(:file?, true) do
      Open3.stub(:capture3, ["", "boom", status_double(false)]) do
        request = {method: "GET", req_uri: "/wiki.cgi?Foo", headers: {}, body: ""}
        response = @qa.run_cgi("wiki.cgi", request)

        assert_equal(500, response[0])
        assert_equal(true, response[1].has_key?("Content-Type"))
        assert_equal(["CGI failed for wiki.cgi\nboom"], response[2])
      end
    end
  end

  # 헤더와 본문 구분이 없으면 전체 출력을 200 OK 본문으로 감싼다
  def test_parse_cgi_out_wraps_headerless_output
    response = @qa.parse_cgi_out("plain body only")

    assert_equal(200, response[0])
    assert_equal(["plain body only"], response[2])
  end

  # Status 헤더가 있으면 HTTP 상태줄로 사용하고, 그 외의 헤더는 응답 헤더로 유지한다
  def test_parse_cgi_out_uses_status_header_and_preserves_other_headers
    response = @qa.parse_cgi_out("Status: 201 Created\r\nX-Test: yes\r\n\r\nbody")

    assert_equal(201, response[0])
    assert_equal(true, response[1].has_key?("X-Test"))
    assert_equal(["body"], response[2])
  end

  # path가 nil이거나 파일이 없으면 not_found를 반환한다
  def test_serve_static_returns_not_found_for_nil_or_missing_file
    assert_equal(404, @qa.serve_static(nil)[0])
    assert_equal(["Not Found\n"], @qa.serve_static(nil)[2])

    in_tmpdir do
      assert_equal(404, @qa.serve_static("missing.gif")[0])
      assert_equal(["Not Found\n"], @qa.serve_static("missing.gif")[2])
    end
  end

  # .gif, .html, .txt 파일을 처리할 수 있다
  def test_serve_static_sets_content_type_by_extension
    in_tmpdir do
      File.binwrite("logo.gif", "GIF")
      File.write("page.html", "<p>ok</p>")
      File.write("note.txt", "text")

      assert_equal("image/gif", @qa.serve_static("logo.gif")[1]["Content-Type"])
      assert_equal("text/html", @qa.serve_static("page.html")[1]["Content-Type"])
      assert_equal("text/plain", @qa.serve_static("note.txt")[1]["Content-Type"])
    end
  end

  # 파일 내용을 바이너리 모드로 읽어 응답 본문에 넣는다
  def test_serve_static_reads_file_as_body
    in_tmpdir do
      File.binwrite("logo.gif", "GIF89a")

      response = @qa.serve_static("logo.gif")

      assert_equal(["GIF89a"], response[2])
    end
  end

  # 응답 객체에는 HTTP 응답 상태 코드를 포함한다
  def test_make_resp_includes_http_status_line
    response = @qa.make_resp("201 Created", body: "ok")

    assert_equal(201, response[0])
  end

  # 호출자가 넘긴 헤더를 응답에 병합한다
  def test_make_resp_merges_headers_sent_by_client
    response = @qa.make_resp(
      "200 OK",
      {"Content-Type" => "text/html", "X-Test" => "yes"},
      body: "ok"
    )

    assert_equal("text/html", response[1]["Content-Type"])
    assert_equal("yes", response[1]["X-Test"])
  end

  # body의 bytesize로 Content-Length를 계산한다
  def test_make_resp_computes_content_length_from_body_bytes
    response = @qa.make_resp("200 OK", body: "한")

    assert_equal("3", response[1]["Content-Length"])
  end
end
