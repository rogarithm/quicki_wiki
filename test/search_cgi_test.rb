require_relative "test_helper"

class SearchCgiTest < Minitest::Test
  def setup
    @searcher = Quicki::Searcher.new
  end

  # QUERY_STRING에서 search 파라미터 값을 추출한다
  def test_handle_req_extracts_search_param
    in_tmpdir do
      write_template("BODY:$body\nSUMMARY:$summary\n")
      write_page("WikiWord", "Wiki body")

      output = with_env("QUERY_STRING" => "search=Wiki", "CONTENT_LENGTH" => "0") do
        capture_io { @searcher.handle_req }.first
      end

      assert_includes(output, "value=\"Wiki\"")
    end
  end

  # search 파라미터의 + 와 percent-encoding을 디코드한다
  def test_handle_req_decodes_search_query
    in_tmpdir do
      write_template("BODY:$body\n")
      write_page("WikiWord", "wiki.org/path")

      output = with_env("QUERY_STRING" => "search=wiki.org%2Fpath", "CONTENT_LENGTH" => "0") do
        capture_io { @searcher.handle_req }.first
      end

      assert_includes(output, "value=\"wiki.org/path\"")
    end
  end

  # WikiWord 형식의 페이지 파일만 검색 대상으로 포함한다
  def test_handle_req_only_searches_wikiword_files
    in_tmpdir do
      write_template("SUMMARY:$summary\n")
      write_page("WikiWord", "Wiki body")
      File.write("pages/not-a-wiki", "Wiki body")

      output = with_env("QUERY_STRING" => "search=Wiki", "CONTENT_LENGTH" => "0") do
        capture_io { @searcher.handle_req }.first
      end

      assert_includes(output, "1 pages found out of 1 pages searched.")
    end
  end

  # 검색 결과 수를 summary에 반영한다
  def test_handle_req_reflects_hit_count_in_summary
    in_tmpdir do
      write_template("SUMMARY:$summary\n")
      write_page("WikiWord", "Wiki body")
      write_page("MainTopic", "No match")

      output = with_env("QUERY_STRING" => "search=Wiki", "CONTENT_LENGTH" => "0") do
        capture_io { @searcher.handle_req }.first
      end

      assert_includes(output, "1 pages found out of 2 pages searched.")
    end
  end

  # 검색 결과에 따른 요약 문구를 만든다
  def test_handle_req_uses_no_pages_found_summary_for_empty_result
    in_tmpdir do
      write_template("SUMMARY:$summary\n")
      write_page("WikiWord", "Wiki body")

      output = with_env("QUERY_STRING" => "search=NoSuchNeedle", "CONTENT_LENGTH" => "0") do
        capture_io { @searcher.handle_req }.first
      end

      assert_includes(output, "No pages found out of 1 pages searched.")
    end
  end

  # title, page, body, summary를 템플릿에 치환해 최종 HTML을 출력한다
  def test_handle_req_renders_template_variables
    in_tmpdir do
      write_template("TITLE:$title\nPAGE:$page\nSUMMARY:$summary\nBODY:$body\n")
      write_page("WikiWord", "Wiki body")

      output = with_env("QUERY_STRING" => "search=Wiki", "CONTENT_LENGTH" => "0") do
        capture_io { @searcher.handle_req }.first
      end

      assert_includes(output, "TITLE:Search Results")
      assert_includes(output, "PAGE:WelcomeVisitors")
      assert_includes(output, "BODY: <form action=search.cgi>")
    end
  end

  # 페이지 제목이나 본문이 정규식에 매칭되면 hit 수를 증가시킨다
  def test_count_hits_counts_each_matching_page_once
    regex = /\b\w*(Wiki)\w*\b/i
    pages = {"WikiWord" => "Wiki body", "MainTopic" => "Wiki body", "Nope" => "none"}

    assert_equal(2, @searcher.count_hits(regex, pages))
  end

  # 검색어를 input value에 그대로 반영한다
  def test_gen_body_reflects_search_target_in_input_value
    body = @searcher.gen_body("Wiki", /\bWiki\b/i, {})

    assert_includes(body, 'value="Wiki"')
  end

  # 매칭된 요소가 제목/본문인지에 따라 결과 줄을 만든다
  def test_gen_body_uses_title_or_body_match_for_result_line
    regex = /\b\w*(Wiki)\w*\b/i
    pages = {"WikiWord" => "no hit", "MainTopic" => "contains Wiki body"}
    body = @searcher.gen_body("Wiki", regex, pages)

    assert_includes(body, "<a href=wiki.cgi?WikiWord>WikiWord</a> . . . . . .  WikiWord<br>")
    assert_includes(body, "<a href=wiki.cgi?MainTopic>MainTopic</a> . . . . . .  Wiki<br>")
  end

  # 매칭이 하나도 없으면 검색 폼만 포함한 본문을 반환한다
  def test_gen_body_returns_only_search_form_when_no_match_exists
    body = @searcher.gen_body("None", /None/, {"WikiWord" => "body"})

    assert_includes(body, "<form action=search.cgi>")
    refute_includes(body, "<a href=wiki.cgi?")
  end
end
