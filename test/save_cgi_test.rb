require_relative "test_helper"

class SaveCgiTest < Minitest::Test
  def setup
    @writer = Quicki::Writer.new
  end

  # QUERY_STRING이 유효한 WikiWord가 아니면 BadSaveName 예외를 발생시킨다
  def test_handle_req_raises_for_invalid_query_string
    err = with_env("QUERY_STRING" => "invalid-name") do
      assert_raises(RuntimeError) do
        @writer.handle_req
      end
    end

    assert_equal("BadSaveName\n", err.message)
  end

  # CONTENT_LENGTH만큼만 stdin을 읽어 저장 입력으로 사용한다
  def test_handle_req_reads_only_content_length_bytes
    in_tmpdir do
      make_wiki_doc("SavePage") do |doc|
        File.binwrite(doc, "old")
      end
      # gen_body 구현을 흉내내서 입력 길이가 실제로 CONTENT_LENGTH만큼인지 확인한다
      observed_length = nil # 확인할 입력 길이값을 저장한다
      @writer.stub(:gen_body, lambda { |input|
        observed_length = input.bytesize
        {"Text" => "saved", "mode" => "edit"}
      }) do
        with_env("QUERY_STRING" => "SavePage", "CONTENT_LENGTH" => "4") do
          capture_with_stdin("1234ignored") { @writer.handle_req }
        end
      end

      assert_equal(4, observed_length)
    end
  end

  # 백링크 대상이 있으면 대상 페이지 끝에 현재 페이지명을 추가한다
  def test_handle_req_appends_backlink_to_target_page
    in_tmpdir do
      make_wiki_doc("SaveBacklink") do |doc|
        File.binwrite(doc, "")
      end
      make_wiki_doc("MainTopic") do |doc|
        File.binwrite(doc, "topic")
      end

      with_env("QUERY_STRING" => "SaveBacklink", "CONTENT_LENGTH" => "34") do
        capture_with_stdin("Text=Before+%3C%3CMainTopic&mode=edit") { @writer.handle_req }
      end

      assert_equal("topic\n----\nSaveBacklink", File.binread("pages/MainTopic"))
    end
  end

  # 저장 후 브라우저가 페이지 보기 화면으로 이동하도록 redirect 헤더를 출력한다
  def test_handle_req_redirects_to_wiki_after_saving
    in_tmpdir do
      make_wiki_doc("SavePage") do |doc|
        File.binwrite(doc, "old")
      end

      out, _err = with_env("QUERY_STRING" => "SavePage", "CONTENT_LENGTH" => "20") do
        capture_with_stdin("Text=hello&mode=edit") { @writer.handle_req }
      end

      assert_equal("Status: 302 Found\nLocation: wiki.cgi?SavePage\n\n", out)
    end
  end

  # application/x-www-form-urlencoded 본문을 key-value 해시로 파싱한다
  def test_gen_body_parses_form_encoded_pairs
    body = @writer.gen_body("Text=Line+One&mode=edit")

    assert_equal({"Text" => "Line One", "mode" => "edit"}, body)
  end

  # 파싱한 해시의 key, value를 각각 + 문자를 공백으로 디코드, percent-encoding된 값을 원래 바이트로 복원 처리한다
  def test_gen_body_decodes_plus_and_percent_encoded_characters
    body = @writer.gen_body("Te%78t=A%26B+One")

    assert_equal({"Text" => "A&B One"}, body)
  end

  # 변환된 본문, 백링크 대상, 파일 모드를 함께 반환한다
  def test_gen_text_returns_text_backlink_and_file_mode
    result = @writer.gen_text("Text" => "Hello", "mode" => "edit")

    assert_equal(["Hello", nil, "w"], result)
  end

  # 본문의 줄바꿈을 처리한다
  def test_gen_text_normalizes_line_endings
    # \n이 이미 있는 경우 \r만 제거
    text, = @writer.gen_text("Text" => "a\r\nb\r", "mode" => "edit")
    assert_equal("a\nb", text)

    # \n이 없으면 \r을 \n으로 변환
    text2, = @writer.gen_text("Text" => "a\rb", "mode" => "edit")
    assert_equal("a\nb", text2)
  end

  # <<WikiWord 패턴이 있으면 << 를 제거하고 링크 대상 이름만 본문에 남긴다
  def test_gen_text_extracts_backlink_target
    text, backlink_target, = @writer.gen_text("Text" => "Before <<MainTopic After", "mode" => "edit")

    assert_equal("Before MainTopic After", text)
    assert_equal("MainTopic", backlink_target)
  end

  # append 모드이면 본문 앞에 구분선과 빈 줄을 추가한다
  def test_gen_text_prefixes_separator_for_append_mode
    text, _target, mode = @writer.gen_text("Text" => "Appended", "mode" => "append")

    assert_equal("\n----\n\nAppended", text)
    assert_equal("a", mode)
  end
end
