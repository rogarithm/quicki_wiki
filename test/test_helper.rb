require "minitest/autorun"
require "stringio"
require "tmpdir"
require "fileutils"
require "open3"
require "rack/mock"
require "rack/test"

TEST_ROOT = File.expand_path("..", __dir__)

load File.join(TEST_ROOT, "quicki.rb")
load File.join(TEST_ROOT, "wiki.cgi")
load File.join(TEST_ROOT, "edit.cgi")
load File.join(TEST_ROOT, "save.cgi")
load File.join(TEST_ROOT, "search.cgi")
load File.join(TEST_ROOT, "changes.cgi")
load File.join(TEST_ROOT, "refcount.cgi")

module QuickiTestHelpers
  def with_env(test_env_vars)
    env_vars = {}
    # test_env_vars의 키 중 env_vars에 등록된 키가 있으면 복구 용도로 그 키값 쌍을 저장해둔다
    test_env_vars.each_key do |k|
      env_vars[k] = ENV[k] if ENV.key?(k)
    end

    # test_env_vars의 값으로 env 값을 설정한다
    test_env_vars.each do |k, v|
      ENV[k] = v
    end

    yield
  ensure
    # 원래 env에 등록된 값을 복구한다
    env_vars.each do |k, v|
      ENV[k] = v
    end
  end

  def in_tmpdir
    Dir.mktmpdir("quicki-test") do |dir|
      Dir.chdir(dir) do
        yield dir
      end
    end
  end

  def write_template(contents = "$title\n$page\n$summary\n$body\n$action\n")
    File.write("template.html", contents)
  end

  def make_wiki_doc(doc_name)
    FileUtils.mkdir_p("pages")
    File.open(File.join("pages", doc_name), "w") do |f|
      yield f
    end
  end

  # 표준 입력으로부터 읽는 동작을 흉내낸다
  # STDIN.read(ENV.fetch("CONTENT_LENGTH", "0").to_i)
  # 표준 출력으로 content_length 환경변수에 설정된 길이만큼의 바이트를 읽어온다
  def capture_with_stdin(stdin_data = "")
    out, err = capture_io do
      STDIN.stub(:read, lambda { |length|
        stdin_data.byteslice(0, length)
      }) { yield }
    end
    [out, err]
  end

  def status_double(success)
    Object.new.tap do |obj|
      obj.define_singleton_method(:success?) { success }
    end
  end
end

class Object
  def stub name, val_or_callable, &block
    new_name = "__stub__#{name}"

    metaclass = class << self; self; end

    metaclass.send :alias_method, new_name, name

    metaclass.send :define_method, name do |*args, **kwargs, &blk|
      if val_or_callable.respond_to?(:call)
        val_or_callable.call(*args, **kwargs, &blk)
      else
        val_or_callable
      end
    end

    block.call(self)
  ensure
    metaclass.send :undef_method, name
    metaclass.send :alias_method, name, new_name
    metaclass.send :undef_method, new_name
  end
end

class Minitest::Test
  include QuickiTestHelpers
end
