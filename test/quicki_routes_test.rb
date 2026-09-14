require_relative "test_helper"

class QuickiRoutesTest < Minitest::Test
  include Rack::Test::Methods

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
    File.stub(:file?, true) do
      Open3.stub(:capture3, ["Status: 200 OK\n\nhello", "", status_double(true)]) do
        get "/wiki.cgi?Foo"
        assert_equal(200, last_response.status)
        assert_includes(last_response.errors, "GET /wiki.cgi?Foo -> wiki.cgi")
      end
    end
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
end
