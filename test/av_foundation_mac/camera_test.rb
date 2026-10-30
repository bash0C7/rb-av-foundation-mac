# frozen_string_literal: true

require "test_helper"
require "tmpdir"

class AVFoundationMacCameraTest < Test::Unit::TestCase
  include CameraGate

  def setup
    @device_id = camera_device_id
  end

  def teardown
    AVFoundationMac.close_session
  end

  test "snapshot writes a JPEG by default" do
    Dir.mktmpdir do |dir|
      out = File.join(dir, "snap.jpg")
      assert_equal(out, AVFoundationMac.snapshot(@device_id, out))
      assert_equal("\xFF\xD8\xFF".b, File.binread(out, 3))
      assert_operator(File.size(out), :>, 10_000)
    end
  end

  test "snapshot writes a HEIC fitted into width x height" do
    Dir.mktmpdir do |dir|
      out = File.join(dir, "snap.heic")
      assert_equal(out, AVFoundationMac.snapshot(@device_id, out, format: :heic, width: 640, height: 480, quality: 0.7))
      header = File.binread(out, 12)
      assert_equal("ftyp", header[4, 4])
      assert_include(%w[heic mif1 heix], header[8, 4])
      width, height = image_size(out)
      assert_operator(width, :<=, 640)
      assert_operator(height, :<=, 480)
      assert_true(width == 640 || height == 480, "expected one side to touch the bound, got #{width}x#{height}")
    end
  end

  test "snapshot returns an empty string when the parent directory does not exist" do
    assert_equal("", AVFoundationMac.snapshot(@device_id, "/nonexistent-dir/snap.jpg"))
  end

  test "open_session, capture_frame, close_session round trip" do
    Dir.mktmpdir do |dir|
      assert_equal("ok", AVFoundationMac.open_session(@device_id, format: :heic, width: 320, height: 320))
      first = File.join(dir, "a.heic")
      second = File.join(dir, "b.heic")
      assert_equal(first, AVFoundationMac.capture_frame(first))
      assert_equal(second, AVFoundationMac.capture_frame(second))
      assert_equal("ftyp", File.binread(second, 8)[4, 4])
      assert_operator(image_size(second).max, :<=, 320)
      assert_nil(AVFoundationMac.close_session)
      assert_equal("", AVFoundationMac.capture_frame(File.join(dir, "c.heic")))
    end
  end

  test "open_session replaces the open session and its encode settings" do
    Dir.mktmpdir do |dir|
      assert_equal("ok", AVFoundationMac.open_session(@device_id, format: :heic))
      assert_equal("ok", AVFoundationMac.open_session(@device_id))
      out = File.join(dir, "frame.jpg")
      assert_equal(out, AVFoundationMac.capture_frame(out))
      assert_equal("\xFF\xD8\xFF".b, File.binread(out, 3))
    end
  end

  test "snapshot captures inside a Ractor" do
    Dir.mktmpdir do |dir|
      out = File.join(dir, "snap.jpg")
      port = Ractor::Port.new
      ractor = Ractor.new(port, @device_id, out) { |reply, id, path| reply << AVFoundationMac.snapshot(id, path) }
      ractor.join
      assert_equal(out, port.receive)
      assert_equal("\xFF\xD8\xFF".b, File.binread(out, 3))
    end
  end

  test "snapshot releases the GVL while it waits for the camera" do
    ticks = 0
    ticker = Thread.new { loop { ticks += 1; sleep 0.01 } }
    Dir.mktmpdir { |dir| AVFoundationMac.snapshot(@device_id, File.join(dir, "snap.jpg")) }
    ticker.kill
    assert_operator(ticks, :>, 50)
  end

  test "Thread#raise ends a waiting snapshot at once" do
    Dir.mktmpdir do |dir|
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      worker = Thread.new { AVFoundationMac.snapshot(@device_id, File.join(dir, "snap.jpg")) }
      sleep 0.5
      worker.raise(RuntimeError, "stop")
      assert_raise_message("stop") { worker.join }
      assert_operator(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started, :<, 1.5)
    end
  end

  test "Thread#raise ends a warming open_session and leaves no session" do
    Dir.mktmpdir do |dir|
      worker = Thread.new { AVFoundationMac.open_session(@device_id) }
      sleep 0.5
      worker.raise(RuntimeError, "stop")
      assert_raise_message("stop") { worker.join }
      assert_equal("", AVFoundationMac.capture_frame(File.join(dir, "frame.jpg")))
    end
  end
end
