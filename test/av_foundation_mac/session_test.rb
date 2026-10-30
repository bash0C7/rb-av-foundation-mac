# frozen_string_literal: true

require "test_helper"
require "tmpdir"

class AVFoundationMacSessionTest < Test::Unit::TestCase
  def teardown
    AVFoundationMac.close_session
  end

  test "capture_frame returns an empty string and writes nothing without an open session" do
    Dir.mktmpdir do |dir|
      out = File.join(dir, "frame.jpg")
      assert_equal("", AVFoundationMac.capture_frame(out))
      assert_false(File.exist?(out))
    end
  end

  test "close_session returns nil and can be called repeatedly" do
    assert_nil(AVFoundationMac.close_session)
    assert_nil(AVFoundationMac.close_session)
  end

  test "open_session returns an empty string for an unknown device" do
    assert_equal("", AVFoundationMac.open_session("no-such-device"))
  end

  test "capture_frame returns an empty string after a failed open_session" do
    AVFoundationMac.open_session("no-such-device")
    Dir.mktmpdir do |dir|
      assert_equal("", AVFoundationMac.capture_frame(File.join(dir, "frame.jpg")))
    end
  end

  test "concurrent open_session and close_session calls from many threads finish" do
    threads = 8.times.map do |i|
      Thread.new { i.even? ? AVFoundationMac.open_session("no-such-device") : AVFoundationMac.close_session }
    end
    assert_equal([""] * 4, threads.map(&:value).compact)
  end
end
