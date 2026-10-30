# frozen_string_literal: true

require "test_helper"
require "tmpdir"

class AVFoundationMacArgumentsTest < Test::Unit::TestCase
  test "snapshot rejects an unknown format" do
    Dir.mktmpdir do |dir|
      error = assert_raise(ArgumentError) do
        AVFoundationMac.snapshot("no-such-device", File.join(dir, "x.png"), format: :png)
      end
      assert_match(/png/, error.message)
    end
  end

  test "snapshot rejects a format that is not a Symbol" do
    Dir.mktmpdir do |dir|
      assert_raise(TypeError) { AVFoundationMac.snapshot("no-such-device", File.join(dir, "x.jpg"), format: "jpeg") }
    end
  end

  test "snapshot rejects an unknown keyword" do
    Dir.mktmpdir do |dir|
      error = assert_raise(ArgumentError) do
        AVFoundationMac.snapshot("no-such-device", File.join(dir, "x.jpg"), fromat: :heic)
      end
      assert_match(/fromat/, error.message)
    end
  end

  test "snapshot rejects a positional hash in place of keywords" do
    Dir.mktmpdir do |dir|
      assert_raise(ArgumentError) { AVFoundationMac.snapshot("no-such-device", File.join(dir, "x.jpg"), { format: :heic }) }
    end
  end

  test "snapshot rejects a device id containing NUL" do
    Dir.mktmpdir do |dir|
      assert_raise(ArgumentError) { AVFoundationMac.snapshot("a\0b", File.join(dir, "x.jpg")) }
    end
  end

  test "open_session rejects an unknown format" do
    assert_raise(ArgumentError) { AVFoundationMac.open_session("no-such-device", format: :png) }
  end

  test "open_session rejects an unknown keyword" do
    assert_raise(ArgumentError) { AVFoundationMac.open_session("no-such-device", qualty: 0.5) }
  end

  test "open_session accepts every documented keyword" do
    assert_equal("", AVFoundationMac.open_session("no-such-device", format: :heic, width: 640, height: 480, quality: 0.5))
  end

  test "string arguments accept objects that respond to to_str" do
    path = Object.new
    def path.to_str = "/nonexistent/x.jpg"
    id = Object.new
    def id.to_str = "no-such-device"
    assert_equal("", AVFoundationMac.snapshot(id, path))
    assert_equal("", AVFoundationMac.open_session(id))
    assert_equal("", AVFoundationMac.capture_frame(path))
  end

  test "capture_frame rejects a non-String path" do
    assert_raise(TypeError) { AVFoundationMac.capture_frame(nil) }
  end
end
