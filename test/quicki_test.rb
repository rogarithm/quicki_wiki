require_relative "test_helper"

class QuickiCoreTest < Minitest::Test
  # 소켓에서 첫 요청 라인을 읽지 못하면 nil을 반환한다
  def test_parse_req_returns_nil_when_request_line_is_missing
    assert_nil(parse_req(StringIO.new))
  end

  # GET 요청에서 method, req_uri, headers, 빈 body를 올바르게 파싱한다
  def test_parse_req_parses_get_request
    io = StringIO.new("GET /wiki.cgi?Foo HTTP/1.0\r\nHost: example\r\nReferer: here\r\n\r\n")

    req = parse_req(io)

    assert_equal("GET", req[:method])
    assert_equal("/wiki.cgi?Foo", req[:req_uri])
    assert_equal("example", req[:headers]["host"])
    assert_equal("here", req[:headers]["referer"])
    assert_equal("", req[:body])
  end

  # POST 요청에서 Content-Length 길이만큼 body를 읽는다
  def test_parse_req_reads_post_body_using_content_length
    io = StringIO.new("POST /save.cgi?Page HTTP/1.0\r\nContent-Length: 7\r\n\r\nabc=123XYZ")

    req = parse_req(io)

    assert_equal("abc=123", req[:body])
  end

  # 헤더 이름을 모두 소문자로 정규화해 저장한다
  def test_parse_req_normalizes_header_names
    io = StringIO.new("GET / HTTP/1.0\r\nX-Custom-Header: Value\r\n\r\n")

    req = parse_req(io)

    assert_equal("Value", req[:headers]["x-custom-header"])
  end

  # 빈 줄을 만나면 헤더 파싱을 멈추고 이후를 body로 처리한다
  def test_parse_req_stops_headers_at_blank_line
    io = StringIO.new("POST / HTTP/1.0\r\nContent-Length: 4\r\n\r\nbodyIGNORED")

    req = parse_req(io)

    assert_equal("body", req[:body])
  end

  # 요청 라인에 method 또는 req_uri가 없으면 nil을 반환한다
  def test_parse_req_returns_nil_when_request_line_is_incomplete
    assert_nil(parse_req(StringIO.new("GET\r\n\r\n")))
  end

  # 요청 uri로부터 cgi 경로를 추출한다
  def test_find_cgi_extracts_cgi_path_from_request_uri
    # 기본값 처리
    assert_equal("wiki.cgi", find_cgi("/"))

    assert_equal("search.cgi", find_cgi("/search.cgi?search=Wiki"))
    assert_equal("logo.gif", find_cgi("/logo%2Egif"))
  end

  # CGI가 아닌 경로는 정적 파일 이름 그대로 반환한다
  def test_find_cgi_returns_static_filename_for_non_cgi_path
    assert_equal("logo.gif", find_cgi("/logo.gif"))
  end

  # 허용 목록에 없는 CGI 이름이거나 매핑된 .cgi 파일이 실제로 없으면 not_found를 반환한다
  def test_run_cgi_returns_not_found_for_unknown_or_missing_script
    assert_match("404 Not Found", run_cgi("unknown.cgi", method: "GET", req_uri: "/", headers: {}, body: ""))

    File.stub(:file?, false) do
      assert_match("404 Not Found", run_cgi("wiki.cgi", method: "GET", req_uri: "/", headers: {}, body: ""))
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
      response = run_cgi("save.cgi", request)

      assert_match("201 Created", response)
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
        response = run_cgi("wiki.cgi", method: "GET", req_uri: "/wiki.cgi?Foo", headers: {}, body: "")

        assert_match("HTTP/1.0 202 Accepted", response)
        assert_match("X-Test: yes", response)
        assert_match(/\r\n\r\nbody\z/, response)
      end
    end
  end

  # CGI 실행이 실패하면 stderr 내용을 포함한 server_error를 반환한다
  def test_run_cgi_returns_server_error_when_cgi_fails
    File.stub(:file?, true) do
      Open3.stub(:capture3, ["", "boom", status_double(false)]) do
        response = run_cgi("wiki.cgi", method: "GET", req_uri: "/wiki.cgi?Foo", headers: {}, body: "")

        assert_match("500 Internal Server Error", response)
        assert_match("CGI failed for wiki.cgi", response)
        assert_match("boom", response)
      end
    end
  end

  # 헤더와 본문 구분이 없으면 전체 출력을 200 OK 본문으로 감싼다
  def test_parse_cgi_out_wraps_headerless_output
    response = parse_cgi_out("plain body only")

    assert_match("HTTP/1.0 200 OK", response)
    assert_match(/\r\n\r\nplain body only\z/, response)
  end

  # Status 헤더가 있으면 HTTP 상태줄로 사용하고, 그 외의 헤더는 응답 헤더로 유지한다
  def test_parse_cgi_out_uses_status_header_and_preserves_other_headers
    response = parse_cgi_out("Status: 201 Created\r\nX-Test: yes\r\n\r\nbody")

    assert_match("HTTP/1.0 201 Created", response)
    assert_match("X-Test: yes", response)
    refute_match(/^Status:/, response)
  end

  # path가 nil이거나 파일이 없으면 not_found를 반환한다
  def test_serve_static_returns_not_found_for_nil_or_missing_file
    assert_match("404 Not Found", serve_static(nil))

    in_tmpdir do
      assert_match("404 Not Found", serve_static("missing.gif"))
    end
  end

  # .gif, .html, .txt 파일을 처리할 수 있다
  def test_serve_static_sets_content_type_by_extension
    in_tmpdir do
      File.binwrite("logo.gif", "GIF")
      File.write("page.html", "<p>ok</p>")
      File.write("note.txt", "text")

      assert_match("Content-Type: image/gif", serve_static("logo.gif"))
      assert_match("Content-Type: text/html", serve_static("page.html"))
      assert_match("Content-Type: text/plain", serve_static("note.txt"))
    end
  end

  # 파일 내용을 바이너리 모드로 읽어 응답 본문에 넣는다
  def test_serve_static_reads_file_as_body
    in_tmpdir do
      File.binwrite("logo.gif", "GIF89a")

      response = serve_static("logo.gif")

      assert_match(/\r\n\r\nGIF89a\z/, response)
    end
  end

  # HTTP/1.0 상태줄을 포함한 응답 문자열을 만든다
  def test_make_resp_includes_http_status_line
    response = make_resp("201 Created", body: "ok")

    assert_match(/\AHTTP\/1\.0 201 Created\r\n/, response)
  end

  # 호출자가 넘긴 헤더를 응답에 병합한다
  def test_make_resp_merges_headers_sent_by_client
    response = make_resp(
      "200 OK",
      {"Content-Type" => "text/html", "X-Test" => "yes"},
      body: "ok"
    )

    assert_match("Content-Type: text/html", response)
    assert_match("X-Test: yes", response)
  end

  # body의 bytesize로 Content-Length를 계산한다
  def test_make_resp_computes_content_length_from_body_bytes
    response = make_resp("200 OK", body: "한")

    assert_match("Content-Length: 3", response)
  end

  # 헤더와 본문 사이를 CRLF CRLF로 구분한다
  def test_make_resp_separates_headers_and_body_with_crlf
    response = make_resp("200 OK", body: "ok")

    assert_includes(response, "\r\n\r\nok")
  end
end
