require "minitest/autorun"
require "stringio"
require "tmpdir"
require "fileutils"
require "socket"
require "open3"

TEST_ROOT = File.expand_path("..", __dir__)

load File.join(TEST_ROOT, "quicki.rb")
load File.join(TEST_ROOT, "wiki.rb.cgi")
load File.join(TEST_ROOT, "edit.rb.cgi")
load File.join(TEST_ROOT, "save.rb.cgi")
load File.join(TEST_ROOT, "search.rb.cgi")
load File.join(TEST_ROOT, "changes.rb.cgi")
load File.join(TEST_ROOT, "refcount.rb.cgi")

module QuickiTestHelpers
  def with_env(vars)
    old = {}
    vars.each_key do |key|
      old[key] = ENV.key?(key) ? ENV[key] : :__missing__
    end

    vars.each do |key, value|
      if value.nil?
        ENV.delete(key)
      else
        ENV[key] = value
      end
    end

    yield
  ensure
    old.each do |key, value|
      if value == :__missing__
        ENV.delete(key)
      else
        ENV[key] = value
      end
    end
  end

  def in_tmpdir
    Dir.mktmpdir("quicki-test") do |dir|
      Dir.chdir(dir) { yield dir }
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

  def capture_with_stdin(stdin_data = "")
    output, err = capture_io do
      STDIN.stub(:read, lambda { |length = nil|
        length.nil? ? stdin_data : stdin_data.byteslice(0, length)
      }) { yield }
    end
    [output, err]
  end

  def with_stubbed_time(now)
    Time.stub(:now, now) { yield }
  end

  def status_double(success)
    Object.new.tap do |obj|
      obj.define_singleton_method(:success?) { success }
    end
  end
end

class Minitest::Test
  include QuickiTestHelpers
end
