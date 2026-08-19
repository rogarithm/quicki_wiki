require_relative "quicki"
require 'dotenv/load'

use Rack::Auth::Basic, "Quicki Wiki" do |username, password|
  # 운영에서는 환경변수나 별도 설정 파일에서 읽어온다
  Rack::Utils.secure_compare(username, ENV.fetch("WIKI_USER")) &
    Rack::Utils.secure_compare(password, ENV.fetch("WIKI_PASSWORD"))
end

run QuickiApp.new
