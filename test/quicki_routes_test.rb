require_relative "test_helper"

class QuickiRoutesTest < Minitest::Test
  include Rack::Test::Methods

  def setup
    QuickiApp.set :raise_errors, false # 에러를 sinatra 앱 바깥쪽으로 전파되지 않게 한다
    QuickiApp.set :show_exceptions, false # 에러를 페이지로 보여주지 않는다
  end

  def app
    lambda do |env|
      # Rack::Test의 default_host인 example.org는 sinatra에서 허용하는 host 목록에 없다.
      # 이대로는 모든 라우트 호출 시 403으로 응답한다.
      # 이를 막기 위해, sinatra에서 허용하는 host인 localhost를 주입한다
      env["HTTP_HOST"] = "localhost"
      env["SERVER_NAME"] = "localhost"
      QuickiApp.call(env)
    end
  end

  # GET 요청이 Sinatra 라우트를 거쳐 실제 CGI 디스패치까지 도달한다
  def test_get_dispatches_through_sinatra_route
    QuickiApp.set :static, false

    File.stub(:file?, true) do
      Open3.stub(:capture3, ["Status: 200 OK\n\nhello", "", status_double(true)]) do
        get "/wiki.cgi?Foo"
        assert_equal(200, last_response.status)
      end
    end
  ensure
    QuickiApp.set :static, true
  end

  # Content-Length는 sinatra(Sinatra::Response#finish)가 CGI 응답 본문의 bytesize로 계산한다
  def test_content_length_is_computed_by_sinatra
    QuickiApp.set :static, false

    File.stub(:file?, true) do
      Open3.stub(:capture3, ["Content-type: text/html; charset=UTF-8\n\n한", "", status_double(true)]) do
        get "/wiki.cgi?Foo"
        assert_equal("3", last_response.headers["content-length"])
      end
    end
  ensure
    QuickiApp.set :static, true
  end

  # 허용 목록에 없는 CGI 이름이면 not_found를 반환한다
  def test_run_cgi_returns_not_found_for_unknown_or_missing_script
    QuickiApp.set :static, false

    get "/unknown.cgi"
    assert_equal(404, last_response.status)
    assert_equal("text/plain;charset=UTF-8", last_response.content_type)
  ensure
      QuickiApp.set :static, true
  end

  # 매핑된 .cgi 파일이 실제로 없으면 not_found를 반환한다
  def test_run_cgi_returns_not_found_when_backing_script_file_is_missing
    QuickiApp.set :static, false

    File.stub(:file?, false) do
      Open3.stub(:capture3, ->(*) { raise "should not be called" }) do
        get "/wiki.cgi"
        assert_equal(404, last_response.status)
      end
    end
  ensure
    QuickiApp.set :static, true
  end

  # POST 요청 본문이 Sinatra 라우트를 거쳐 CGI의 표준 입력까지 그대로 전달된다
  def test_post_body_reaches_cgi_through_sinatra_route
    env = nil

    File.stub(:file?, true) do
      Open3.stub(:capture3, lambda { |_env, *_args, **kwargs|
        env = _env.merge("stdin" => kwargs[:stdin_data])
        # 저장 후 해당 위키 페이지로 리다이렉션한다
        ["Status: 302 Found\nLocation: wiki.cgi?TestPage\n\n", "", status_double(true)]
      }) do
        post "/save.cgi?TestPage", "Text=hello&mode=edit"
        assert_equal(302, last_response.status)
      end
    end

    assert_equal("Text=hello&mode=edit", env["stdin"])
    assert_equal("20", env["CONTENT_LENGTH"])
  end

  # PUT처럼 등록되지 않은 CGI 관련 메서드는 405를 반환한다
  def test_put_returns_method_not_allowed
    put "/wiki.cgi"
    assert_equal(405, last_response.status)
  end

  def test_patch_returns_method_not_allowed
    patch "/wiki.cgi"
    assert_equal(405, last_response.status)
  end

  def test_delete_returns_method_not_allowed
    delete "/wiki.cgi"
    assert_equal(405, last_response.status)
  end

  def test_options_returns_405_by_sinatra_default
    options "/wiki.cgi"
    assert_equal(405, last_response.status)
  end

  # .gif, .html, .txt 파일을 처리할 수 있다
  def test_serve_static_sets_content_type_by_extension
    original = QuickiApp.settings.public_folder
    in_tmpdir(dirname: "public") do |dir|
      QuickiApp.set :public_folder, dir

      File.binwrite("logo.gif", "GIF")
      File.write("page.html", "<p>ok</p>")
      File.write("note.txt", "text")

      get "/logo.gif"
      assert_equal(200, last_response.status)
      assert_equal("image/gif", last_response.headers["content-type"])

      get "/page.html"
      assert_equal(200, last_response.status)
      assert_equal("text/html;charset=utf-8", last_response.headers["content-type"])

      get "/note.txt"
      assert_equal(200, last_response.status)
      assert_equal("text/plain;charset=utf-8", last_response.headers["content-type"])
    end
  ensure
    QuickiApp.set :public_folder, original
  end

  # path가 nil이거나 파일이 없으면 not_found를 반환한다
  def test_serve_static_returns_not_found_for_nil_or_missing_file
    original = QuickiApp.settings.public_folder
    in_tmpdir(dirname: "public") do |dir|
      QuickiApp.set :public_folder, dir

      get "/missing.gif"
      assert_equal(404, last_response.status)
    end
  ensure
    QuickiApp.set :public_folder, original
  end

  # 파일 내용을 바이너리 모드로 읽어 응답 본문에 넣는다
  def test_serve_static_reads_file_as_body
    original = QuickiApp.settings.public_folder
    in_tmpdir(dirname: "public") do |dir|
      QuickiApp.set :public_folder, dir

      File.binwrite("logo.gif", "GIF89a")

      get "/logo.gif"
      assert_includes(last_response.body, "GIF89a")
    end
  ensure
    QuickiApp.set :public_folder, original
  end

  def test_logging_before_handle_route
    get "/wiki.cgi?Foo"
    assert_includes(last_response.errors, "GET /wiki.cgi?Foo")

    put "/wiki.cgi"
    assert_includes(last_response.errors, "PUT /wiki.cgi")

    patch "/wiki.cgi"
    assert_includes(last_response.errors, "PATCH /wiki.cgi")

    delete "/wiki.cgi"
    assert_includes(last_response.errors, "DELETE /wiki.cgi")

    options "/wiki.cgi"
    assert_includes(last_response.errors, "OPTIONS /wiki.cgi")
  end

  def test_server_error
    orig_handle_meth = QuickiApp.instance_method(:handle)
    QuickiApp.class_eval do
      define_method(:handle) {|_, _| raise StandardError, "msg" }
    end

    get "/wiki.cgi?Foo"
    assert_equal 500, last_response.status
    assert_equal("text/plain;charset=UTF-8", last_response.headers["content-type"])
    assert_includes last_response.body, "StandardError: msg"
  ensure
    QuickiApp.define_method(:handle, orig_handle_meth)
  end
end

class SinatraTest < Minitest::Test
  include Rack::Test::Methods

  def app
    lambda do |env|
      env["HTTP_HOST"] = "localhost"
      env["SERVER_NAME"] = "localhost"
      QuickiApp.call(env)
    end
  end

  # sinatra에서 같은 라우트 패턴 문자열의 인코딩/디코딩된 버전을 동일하게 매칭하는지 확인한다
  def test_decode_path_info_before_route
    # env["sinatra.route"]에 http 메서드와 매칭된 라우트 패턴이 기록된다
    get "/wiki%2ecgi"
    encoded_route = last_request.env["sinatra.route"].split("/")[1].chomp

    get "/wiki.cgi"
    plain_route = last_request.env["sinatra.route"].split("/")[1].chomp

    [encoded_route, plain_route].all? {|r| assert_equal(r, encoded_route)}
    assert_equal(plain_route, encoded_route)
  end

  # 폼 본문이 포함된 요청의 경우, sinatra가 params를 만들면서 폼 본문을 끝까지 읽는다.
  def test_sinatra_reads_form_body_before_route
    post "/save.cgi?TestPage", "Text=hello&mode=edit"

    env = last_request.env

    # rack.input의 읽기 위치가 끝에 가 있다
    assert_equal("Text=hello&mode=edit".bytesize, env["rack.input"].pos)
    # 읽기 위치를 따로 되돌리지 않으면 rack.input은 빈 문자열로 남아있다
    assert_equal("", env["rack.input"].read)

    # 읽은 본문은 rack이 env에 파싱해 둔다
    assert_equal("Text=hello&mode=edit", env["rack.request.form_vars"])
  end
end
