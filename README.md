### 소개

- Ruby로 작성된 간단한 CGI 기반 위키 애플리케이션

### 사용 기술

- Ruby
- minitest

### 실행 방법

프로젝트 루트에서 아래 명령을 실행

```bash
ruby quicki.rb
```

기본 포트는 `8000`이다. 다른 포트로 실행하려면 포트 번호를 인자로 넘기면 된다.

```bash
ruby quicki.rb 9292
```

실행 후 브라우저에서 아래 주소로 접속한다.

```text
http://localhost:8000/
```

### 주요 기능

- 페이지 조회: `/` 또는 `/wiki.cgi?PageName`
- 페이지 편집: `/edit.cgi?PageName`
- 페이지 저장: `save.cgi`
- 검색: `/search.cgi?search=키워드`
- 최근 변경 목록: `/changes.cgi`
- 참조 수 확인: `/refcount.cgi?PageName`

### 테스트

```bash
ruby -e 'ARGV.each { |f| require f }' ./test/*test.rb
```

개별 테스트 실행 시

```bash
ruby test/quicki_test.rb
```

