require_relative "test_helper"

class RefcountCgiTest < Minitest::Test
  def setup
    @counter = Quicki::BacklinkCounter.new
  end

  # pages 디렉터리에서 WikiWord 형식 파일만 집계 대상으로 선택한다
  def test_handle_req_only_uses_wikiword_files
    in_tmpdir do
      write_template("BODY:$body\n")
      make_wiki_doc("WikiWord") do |doc|
        File.binwrite(doc, "MainTopic")
      end
      make_wiki_doc("not-a-wiki") do |doc|
        File.binwrite(doc, "WikiWord")
      end

      output = with_env("QUERY_STRING" => "", "CONTENT_LENGTH" => "0") do
        capture_io { @counter.handle_req }.first
      end

      assert_includes(output, "WikiWord")
      refute_includes(output, "not-a-wiki")
    end
  end

  # 각 페이지 파일 내용을 읽어 페이지명-본문 해시를 구성한다
  def test_handle_req_reads_page_contents_and_renders_template
    in_tmpdir do
      write_template("TITLE:$title\nPAGE:$page\nBODY:$body\n")
      make_wiki_doc("WikiWord") do |doc|
        File.binwrite(doc, "MainTopic")
      end
      make_wiki_doc("MainTopic") do |doc|
        File.binwrite(doc, "")
      end

      output = with_env("QUERY_STRING" => "", "CONTENT_LENGTH" => "0") do
        capture_io { @counter.handle_req }.first
      end

      assert_includes(output, "TITLE:Page References")
      assert_includes(output, "PAGE:http:pagerefs.cgi")
      assert_includes(output, "<table border=0 cellspacing=0 cellpadding=0>")
    end
  end

  # 각 페이지가 참조한 WikiWord를 중복 없이 수집한다
  def test_gen_body_collects_referenced_wikiwords
    pages = {
      "WikiWord" => "MainTopic",
      "MainTopic" => ""
    }

    body = @counter.gen_body(pages)

    assert_includes(body, "<td valign=right>1</td>")
  end

  # 같은 페이지 안에서 동일한 WikiWord가 여러 번 나와도 한 번만 참조로 집계한다
  def test_gen_body_counts_duplicate_links_once_per_page
    pages = {
      "WikiWord" => "MainTopic MainTopic",
      "MainTopic" => ""
    }

    body = @counter.gen_body(pages)

    assert_equal(1, body.scan("<td valign=right>1</td>").length)
  end

  # 어떤 페이지를 참조한 다른 페이지 수를 올바르게 계산한다
  def test_gen_body_counts_referrers_per_page
    pages = {
      "AlphaPage" => "MainTopic",
      "BetaPage" => "MainTopic",
      "MainTopic" => ""
    }

    body = @counter.gen_body(pages)

    assert_includes(body, "<td valign=right>2</td><td>&nbsp;&nbsp;<a href=wiki.cgi?MainTopic>MainTopic</a></td>")
  end

  # 존재하지 않는 대상 WikiWord가 본문에 있어도 refs 해시에는 기록되지만 최종 표에는 실제 파일만 출력한다
  def test_gen_body_excludes_nonexistent_targets_from_final_table
    pages = {
      "WikiWord" => "MissingPage",
      "MainTopic" => ""
    }

    body = @counter.gen_body(pages)

    refute_includes(body, "MissingPage</a>")
    assert_includes(body, "WikiWord")
    assert_includes(body, "MainTopic")
  end
end
