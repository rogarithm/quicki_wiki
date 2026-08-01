require_relative "test_helper"

class ChangesCgiTest < Minitest::Test
  def setup
    @viewer = Quicki::ChangeViewer.new
  end

  # pages 디렉터리에서 WikiWord 형식 파일만 최근 변경 목록 대상으로 선택한다
  def test_handle_req_only_uses_wikiword_files
    in_tmpdir do
      write_template("BODY:$body\n")
      make_wiki_doc("WikiWord") do |doc|
        File.binwrite(doc, "one")
        File.utime(Time.utc(2024, 1, 1), Time.utc(2024, 1, 1), doc)
      end
      make_wiki_doc("not-a-wiki") do |doc|
        File.binwrite(doc, "skip")
      end

      output = with_env("QUERY_STRING" => "", "CONTENT_LENGTH" => "0") do
        capture_io { @viewer.handle_req }.first
      end

      assert_includes(output, "WikiWord")
      refute_includes(output, "not-a-wiki")
    end
  end

  # 파일 수정 시각이 최신인 페이지가 먼저 오도록 정렬한다
  def test_handle_req_orders_pages_by_most_recent_mtime
    in_tmpdir do
      write_template("BODY:$body\n")
      make_wiki_doc("OldPage") do |doc|
        File.binwrite(doc, "one")
        File.utime(Time.utc(2024, 1, 1), Time.utc(2024, 1, 1), doc)
      end
      make_wiki_doc("NewPage") do |doc|
        File.binwrite(doc, "new")
        File.utime(Time.utc(2024, 1, 2), Time.utc(2024, 1, 2), doc)
      end

      output = with_env("QUERY_STRING" => "", "CONTENT_LENGTH" => "0") do
        capture_io { @viewer.handle_req }.first
      end

      assert_operator(output.index("NewPage"), :<, output.index("OldPage"))
    end
  end

  # QUERY_STRING에 max 값이 없으면 25개, 값이 있으면 해당 개수만큼 표시한다
  def test_handle_req_respects_max_parameter
    in_tmpdir do
      write_template("BODY:$body\n")
      make_wiki_doc("FirstPage") do |doc|
        File.binwrite(doc, "1")
      end
      make_wiki_doc("SecondPage") do |doc|
        File.binwrite(doc, "2")
      end

      output = with_env("QUERY_STRING" => "max=1", "CONTENT_LENGTH" => "0") do
        capture_io { @viewer.handle_req }.first
      end

      assert_equal(1, output.scan(/<dd><a href=wiki.cgi\?/).length)
    end
  end

  # title, page, body를 템플릿에 치환해 최종 HTML을 출력한다
  def test_handle_req_renders_template_variables
    in_tmpdir do
      write_template("TITLE:$title\nPAGE:$page\nBODY:$body\n")
      make_wiki_doc("WikiWord") do |doc|
        File.binwrite(doc, "body")
      end

      output = with_env("QUERY_STRING" => "", "CONTENT_LENGTH" => "0") do
        capture_io { @viewer.handle_req }.first
      end

      assert_includes(output, "TITLE:Recent Changes")
      assert_includes(output, "PAGE:http:changes.cgi")
      assert_includes(output, "BODY:<dl>")
    end
  end

  # 같은 날짜의 페이지들은 하나의 dt 아래 연속된 dd로 출력한다
  def test_gen_body_groups_pages_under_same_date
    time = Time.utc(2024, 1, 1, 0, 0, 0)
    body = @viewer.gen_body([[time, "FirstPage"], [time, "SecondPage"]], 25)

    assert_equal(1, body.scan(/<dt>/).length)
    assert_equal(2, body.scan(/<dd><a href=wiki.cgi\?/).length)
  end

  # 날짜가 바뀌면 새 dt를 출력한다
  def test_gen_body_starts_new_group_when_date_changes
    body = @viewer.gen_body([[Time.utc(2024, 1, 2), "NewPage"], [Time.utc(2024, 1, 1), "OldPage"]], 25)

    assert_equal(2, body.scan(/<dt>/).length)
  end

  # 최대 max 개수만큼의 페이지를 출력한다
  def test_gen_body_limits_rows_to_max
    time = Time.utc(2024, 1, 1, 0, 0, 0)
    body = @viewer.gen_body([[time, "FirstPage"], [time, "SecondPage"]], 1)

    assert_equal(1, body.scan(/<dd><a href=wiki.cgi\?/).length)
  end
end
