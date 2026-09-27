### 소개

- Ruby로 작성된 CGI/Sinatra 기반 위키 애플리케이션

### 사용 기술

- Ruby
- minitest
- rack
- sinatra
- puma
- dotenv
- rack-test

### 실행 방법

프로젝트 루트에서 아래 명령을 실행

```bash
bundle install
bundle exec puma
```

기본 포트는 `9292`이다. 다른 포트로 실행하려면 포트 번호를 인자로 넘기면 된다.

```bash
bundle exec puma -p 8000
```

실행 후 브라우저에서 아래 주소로 접속한다.

```text
http://localhost:8000/
```

애플리케이션은 config.ru에서 QuickiApp Sinatra 앱으로 실행된다.<br>GET/POST 요청은 Sinatra 라우트를 거쳐 기존 CGI 스크립트로 디스패치되고, 그 외 메서드는 405 Method Not Allowed로 응답한다.

Rack에서 제공하는 Rack::Auth::Basic과 env gem으로 페이지 접근 권한을 제한한다.<br>.env 파일에 다음과 같이 환경변수 값을 설정하고,
```dotenv
WIKI_USER=user_name
WIKI_PASSWORD=very_complex_password
```
페이지 접근 시 설정한 값을 입력해 페이지 기능을 쓸 수 있다
<img width="1274" height="350" alt="image" src="https://github.com/user-attachments/assets/96d68647-4959-40ec-aa6d-c69b980b76bc" />


### 주요 기능

- 페이지 조회: `/` 또는 `/wiki.cgi?PageName`
- 페이지 편집: `/edit.cgi?PageName`
- 페이지 저장: `save.cgi`
- 검색: `/search.cgi?search=키워드`
- 최근 변경 목록: `/changes.cgi`
- 참조 수 확인: `/refcount.cgi?PageName`

### 정적 파일

이미지 등 정적 자산은 `public/` 디렉터리에서 서빙된다. 위키 문서나 템플릿에서 참조할 이미지를 추가하려면 `public/` 아래에 넣어야 한다.

### 테스트

```bash
ruby -e 'ARGV.each { |f| require f }' ./test/*test.rb
```

개별 테스트 실행 시

```bash
ruby test/quicki_test.rb
```

