require_relative "quicki"
require 'dotenv/load'

# CGI 클래스는 pages/와 template.html을 상대 경로로 읽는다.
# 요청마다 바꾸면 스레드끼리 영향을 주므로, 서버 시작 시 한 번만 프로젝트 루트로 맞춘다
Dir.chdir(QuickiApp::ROOT)

use Rack::Auth::Basic, "Quicki Wiki" do |username, password|
  # 운영에서는 환경변수나 별도 설정 파일에서 읽어온다
  Rack::Utils.secure_compare(username, ENV.fetch("WIKI_USER")) &
    Rack::Utils.secure_compare(password, ENV.fetch("WIKI_PASSWORD"))
end

run QuickiApp
