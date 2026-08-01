require_relative "test_helper"

class EditCgiTest < Minitest::Test
  def setup
    @editor = Quicki::Editor.new
  end

  # QUERY_STRING이 비어 있거나 유효하지 않으면 WelcomeVisitors를 편집 대상으로 선택한다
  def test_handle_req_uses_welcome_visitors_for_invalid_query
    in_tmpdir do
      write_template
      make_wiki_doc("WelcomeVisitors") do |doc|
        File.binwrite(doc, "Body")
      end

      output = with_env("QUERY_STRING" => "not-valid", "CONTENT_LENGTH" => "0") do
        capture_with_stdin { @editor.handle_req }.first
      end

      assert_match("Edit WelcomeVisitors", output)
    end
  end

  # 기존 페이지 존재 여부에 따라 textarea 본문을 렌더링한다
  def test_handle_req_renders_textarea_body_based_on_page_presence
    in_tmpdir do
      write_template
      make_wiki_doc("WelcomeVisitors") do |doc|
        File.binwrite(doc, "A&B")
      end

      existing = with_env("QUERY_STRING" => "WelcomeVisitors", "CONTENT_LENGTH" => "0") do
        capture_with_stdin { @editor.handle_req }.first
      end
      missing = with_env("QUERY_STRING" => "MissingPage", "CONTENT_LENGTH" => "0") do
        capture_with_stdin { @editor.handle_req }.first
      end

      assert_match(/<textarea[^>]*>A&amp;B<\/textarea>/, existing)
      assert_match(/<textarea[^>]*><\/textarea>/, missing)
    end
  end

  # POST body에 append가 포함되면 댓글을 쓸 수 있게 추가 모드 제목을 쓰고, 본문을 비우고 hidden mode를 append로 설정한다
  def test_handle_req_switches_to_append_mode
    in_tmpdir do
      write_template
      make_wiki_doc("GuestBook") do |doc|
        File.binwrite(doc, "Existing")
      end

      output = with_env("QUERY_STRING" => "GuestBook", "CONTENT_LENGTH" => "8") do
        capture_with_stdin("append=1") { @editor.handle_req }.first
      end

      assert_match("Add comment to GuestBook", output)
      assert_match(/<textarea[^>]*><\/textarea>/, output)
      assert_match(/name="mode" value="append"/, output)
    end
  end

  # 템플릿 변수 title, page, body를 치환해 최종 HTML을 출력한다
  def test_handle_req_renders_template_variables
    in_tmpdir do
      write_template("TITLE:$title\nPAGE:$page\nBODY:$body\n")
      make_wiki_doc("WelcomeVisitors") do |doc|
        File.binwrite(doc, "Body")
      end

      output = with_env("QUERY_STRING" => "WelcomeVisitors", "CONTENT_LENGTH" => "0") do
        capture_with_stdin { @editor.handle_req }.first
      end

      assert_includes(output, "TITLE:Edit WelcomeVisitors")
      assert_includes(output, "PAGE:WelcomeVisitors")
      assert_includes(output, "BODY:\t<form method=post action=\"save.cgi?WelcomeVisitors\">")
    end
  end

  # 일반 페이지 본문에서 &, <, > 문자를 HTML escape한다
  def test_gen_body_escapes_html_characters
    assert_equal("&amp;&lt;&gt;", @editor.gen_body("&<>"))
  end

  # MARK 구분자가 포함된 숨김 필드 페이지에서는 text 필드만 추출한다
  def test_gen_body_extracts_text_field_from_hidden_field_page
    source = "text#{Quicki::Editor::MARK}Visible#{Quicki::Editor::MARK}other#{Quicki::Editor::MARK}Hidden"

    assert_equal("Visible", @editor.gen_body(source))
  end

  # MARK 구분자는 최종 textarea 본문에 남기지 않는다
  def test_gen_body_does_not_leave_mark_in_output
    source = "text#{Quicki::Editor::MARK}Visible"

    refute_includes(@editor.gen_body(source), Quicki::Editor::MARK)
  end
end
