require_relative "test_helper"

class WikiBrowserTest < Minitest::Test
  def setup
    @browser = Quicki::Browser.new
  end

  # QUERY_STRING이 비어 있거나 WikiWord 형식이 아니면 WelcomeVisitors를 렌더링한다
  def test_handle_req_renders_welcome_visitors_for_blank_or_invalid_query
    in_tmpdir do
      write_template
      make_wiki_doc("WelcomeVisitors") do |doc|
        File.binwrite(doc, "Welcome body")
      end

      out, _err = with_env("QUERY_STRING" => "") do
        capture_io { @browser.handle_req }
      end

      assert_match("Welcome Visitors", out)
      assert_match("Welcome body", out)
    end
  end

  # QUERY_STRING이 유효한 WikiWord이면 해당 페이지를 렌더링한다
  def test_handle_req_renders_requested_page
    in_tmpdir do
      write_template
      make_wiki_doc("WikiWord") do |doc|
        File.binwrite(doc, "Page body")
      end

      out, _err = with_env("QUERY_STRING" => "WikiWord") do
        capture_io { @browser.handle_req }
      end

      assert_match("Wiki Word", out)
      assert_match("Page body", out)
    end
  end

  # 대상 페이지 파일이 없으면 미존재 페이지 안내 문구를 출력한다
  def test_handle_req_shows_missing_page_message
    in_tmpdir do
      write_template

      out, _err = with_env("QUERY_STRING" => "MissingPage") do
        capture_io { @browser.handle_req }
      end

      assert_match(/"MissingPage" does not yet exist/, out)
    end
  end

  # 사전에 추출한 인라인 URL placeholder를 최종 HTML로 복원한다
  def test_render_wiki_doc_restores_in_place_urls
    html = @browser.render_wiki_doc("visit http://example.com/path")

    assert_includes(html, '<a href="http://example.com/path">http://example.com/path</a>')
  end

  # 문서 끝에서 아직 열린 블록 태그를 모두 닫는다
  def test_render_wiki_doc_closes_open_block_tags
    html = @browser.render_wiki_doc("* item")

    assert_includes(html, "<UL><li> item\n</UL>\n<p>")
  end

  # 추출한 URL을 MARK 기반 placeholder로 치환한다
  def test_extract_in_place_urls_replaces_urls_with_mark_placeholders
    urls, line = @browser.extract_in_place_urls([], "see http://example.com")

    assert_equal(["http://example.com"], urls)
    assert_match(/\Asee #{Regexp.escape(Quicki::Browser::MARK)}0#{Regexp.escape(Quicki::Browser::MARK)}\z/, line)
  end

  # 들여쓴 줄은 PRE 후보로 감지하되 본문 내용은 바꾸지 않는다
  def test_sub2html_detects_indented_lines_for_pre
    line, has_matching, _rule, _match = @browser.sub2html(" indented", false)

    assert_equal(" indented", line)
    assert_equal(true, has_matching)
  end

  # 빈 줄, *, #, 정의 목록, n. 형식, H2, H3, H4 제목 마커, blockquote 마커를 적절히 처리한다
  def test_sub2html_processes_supported_rules
    assert_equal(
      ["<p>", true],
      @browser.sub2html("", false).first(2)
    )
    assert_equal(
      "<li> item",
      @browser.sub2html("* item", false)[0]
    )
    assert_equal(
      "<li> item",
      @browser.sub2html("# item", false)[0]
    )
    assert_equal(
      "<dt>term<dd>value",
      @browser.sub2html(":term: value", false)[0]
    )
    assert_equal(
      "<li> item",
      @browser.sub2html("1. item", false)[0]
    )
    assert_equal(
      "head",
      @browser.sub2html("!!head", false)[0]
    )
    assert_equal(
      "head",
      @browser.sub2html("!!!head", false)[0]
    )
    assert_equal(
      "head",
      @browser.sub2html("!!!!head", false)[0]
    )
    assert_equal(
      "quote",
      @browser.sub2html('""quote', false)[0]
    )
  end

  # 매칭되는 규칙이 없으면 has_matching=false와 원본 줄을 반환한다
  def test_sub2html_returns_original_line_for_non_matching_rule
    line, has_matching, = @browser.sub2html("plain text", false)

    assert_equal("plain text", line)
    assert_equal(false, has_matching)
  end

  # PRE 규칙, 별표 목록 규칙, 샵 목록 규칙, 정의 목록 규칙, 숫자 목록 규칙, 제목 및 blockquote 규칙을 적절히 처리한다
  def test_wrap_block_tags_emits_expected_tags_for_supported_rules
    assert_equal(
      "",
      @browser.wrap_block_tags(
        Quicki::BlockTagger.new,
        @browser.sub2html("* item one\n\n* item two", false)[2],
        @browser.sub2html("* item one\n\n* item two", false)[3]
      )
    )

    assert_equal(
      "<PRE>",
      @browser.wrap_block_tags(
        Quicki::BlockTagger.new,
        @browser.sub2html(" indented", false)[2],
        @browser.sub2html(" indented", false)[3]
      )
    )
    assert_equal(
      "<UL>",
      @browser.wrap_block_tags(
        Quicki::BlockTagger.new,
        @browser.sub2html("* item", false)[2],
        @browser.sub2html("* item", false)[3]
      )
    )
    assert_equal(
      "<OL>",
      @browser.wrap_block_tags(
        Quicki::BlockTagger.new,
        @browser.sub2html("# item", false)[2],
        @browser.sub2html("# item", false)[3]
      )
    )
    assert_equal(
      "<DL>",
      @browser.wrap_block_tags(
        Quicki::BlockTagger.new,
        @browser.sub2html(":term: value", false)[2],
        @browser.sub2html(":term: value", false)[3]
      )
    )
    assert_equal(
      "<OL>",
      @browser.wrap_block_tags(
        Quicki::BlockTagger.new,
        @browser.sub2html("1. item", false)[2],
        @browser.sub2html("1. item", false)[3]
      )
    )
    assert_equal(
      "<H2>",
      @browser.wrap_block_tags(
        Quicki::BlockTagger.new,
        @browser.sub2html("!!head", false)[2],
        @browser.sub2html("!!head", false)[3]
      )
    )
    assert_equal(
      "<BLOCKQUOTE>",
      @browser.wrap_block_tags(
        Quicki::BlockTagger.new,
        @browser.sub2html('""quote', false)[2],
        @browser.sub2html('""quote', false)[3]
      )
    )
  end

  # 블록 규칙이 아니면 빈 문자열을 반환한다
  def test_wrap_block_tags_returns_empty_string_for_non_block_rule
    assert_equal("", @browser.wrap_block_tags(Quicki::BlockTagger.new, nil, nil))
  end

  # 현재 depth보다 깊어져야 하면 필요한 만큼 여는 태그를 추가한다
  def test_emit_code_opens_tags_until_depth_is_reached
    bt = Quicki::BlockTagger.new

    assert_equal("<UL><UL>", bt.transition_to("UL", 2))
    assert_equal(["UL", "UL"], bt.open_tags)
  end

  # 현재 depth보다 얕아지면 초과된 태그를 닫고 p 구분자를 추가한다
  def test_emit_code_closes_tags_when_depth_decreases
    bt = Quicki::BlockTagger.new(["UL", "UL"])

    assert_equal("</UL>\n<p>", bt.transition_to("UL", 1))
    assert_equal(["UL"], bt.open_tags)
  end

  # depth는 같고 태그 종류만 바뀌면 기존 태그를 닫고 새 태그를 연다
  def test_emit_code_switches_tag_when_tag_type_changes
    bt = Quicki::BlockTagger.new(["UL"])

    assert_equal("</UL>\n<OL>", bt.transition_to("OL", 1))
    assert_equal(["OL"], bt.open_tags)
  end

  # 현재 스택과 요청된 태그/깊이가 같으면 빈 문자열을 반환한다
  def test_emit_code_returns_empty_string_when_stack_already_matches
    bt = Quicki::BlockTagger.new(["UL"])

    assert_equal("", bt.transition_to("UL", 1))
  end

  # 긴 javascript URL은 표시 텍스트만 축약하고 href에는 원본 값을 유지한다
  def test_in_place_url_truncates_javascript_label_only
    long_url = "javascript:abcdefghijklmnopqrstuvwxyz1234567890"
    html = @browser.in_place_url([long_url], 0)

    assert_includes(html, "href=\"#{long_url}\"")
    assert_includes(html, "javascript:abcdefghijklmnopqrstuvwxyz123 ...") # 표시되는 텍스트
  end
end
