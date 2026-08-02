require_relative "test_helper"

class SearchCgiTest < Minitest::Test
  def setup
    @searcher = Quicki::Searcher.new
  end

  # QUERY_STRING에서 search 파라미터 값을 추출한다
  def test_handle_req_extracts_search_param
    in_tmpdir do
      write_template("BODY:$body\nSUMMARY:$summary\n")
      make_wiki_doc("WikiWord") do |doc|
        File.binwrite(doc, "Wiki body")
      end

      out, _err = with_env("QUERY_STRING" => "search=Wiki") do
        capture_io { @searcher.handle_req }
      end

      assert_includes(out, "value=\"Wiki\"")
    end
  end

  # search 파라미터의 + 와 percent-encoding을 디코드한다
  def test_handle_req_decodes_search_query
    in_tmpdir do
      write_template("BODY:$body\n")
      make_wiki_doc("WikiWord") do |doc|
        File.binwrite(doc, "wiki.org/path")
      end

      out, _err = with_env("QUERY_STRING" => "search=wiki.org%2Fpath") do
        capture_io { @searcher.handle_req }
      end

      assert_includes(out, "value=\"wiki.org/path\"")
    end
  end

  # WikiWord 형식의 페이지 파일만 검색 대상으로 포함한다
  def test_handle_req_only_searches_wikiword_files
    in_tmpdir do
      write_template("SUMMARY:$summary\n")
      make_wiki_doc("WikiWord") do |doc|
        File.binwrite(doc, "Wiki body")
      end
      make_wiki_doc("not-a-wiki") do |doc|
        File.binwrite(doc, "Wiki body")
      end

      out, _err = with_env("QUERY_STRING" => "search=Wiki") do
        capture_io { @searcher.handle_req }
      end

      assert_includes(out, "1 pages found out of 1 pages searched.")
    end
  end

  # 검색 시 찾아본 위키 문서 수를 summary에 반영한다
  def test_handle_req_reflects_hit_count_in_summary
    in_tmpdir do
      write_template("SUMMARY:$summary\n")
      make_wiki_doc("WikiWord") do |doc|
        File.binwrite(doc, "Wiki body")
      end
      make_wiki_doc("MainTopic") do |doc|
        File.binwrite(doc, "No match")
      end

      out, _err = with_env("QUERY_STRING" => "search=Wiki") do
        capture_io { @searcher.handle_req }
      end

      assert_includes(out, "1 pages found out of 2 pages searched.")
    end
  end

  # 검색 결과에 따른 요약 문구를 만든다
  def test_handle_req_uses_no_pages_found_summary_for_empty_result
    in_tmpdir do
      write_template("SUMMARY:$summary\n")
      make_wiki_doc("WikiWord") do |doc|
        File.binwrite(doc, "Wiki body")
      end

      out, _err = with_env("QUERY_STRING" => "search=NoSuchNeedle") do
        capture_io { @searcher.handle_req }
      end

      assert_includes(out, "No pages found out of 1 pages searched.")
    end
  end

  # title, page, body, summary를 템플릿에 치환해 최종 HTML을 출력한다
  def test_handle_req_renders_template_variables
    in_tmpdir do
      write_template("TITLE:$title\nPAGE:$page\nSUMMARY:$summary\nBODY:$body\n")
      make_wiki_doc("WikiWord") do |doc|
        File.binwrite(doc, "Wiki body")
      end

      out, _err = with_env("QUERY_STRING" => "search=Wiki") do
        capture_io { @searcher.handle_req }
      end

      assert_includes(out, "TITLE:Search Results")
      assert_includes(out, "PAGE:WelcomeVisitors")
      assert_includes(out, "BODY: <form action=search.cgi>")
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
    body = @searcher.gen_body("Wiki", /\b\w*Wiki\w*\b/i, {})

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
    body = @searcher.gen_body("None", /\b\w*(None)\w*\b/i, {"WikiWord" => "body"})

    assert_includes(body, "<form action=search.cgi>")
    refute_includes(body, "<a href=wiki.cgi?")
  end
end
