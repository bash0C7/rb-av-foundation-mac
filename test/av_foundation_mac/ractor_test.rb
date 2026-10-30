# frozen_string_literal: true

require "test_helper"

class AVFoundationMacRactorTest < Test::Unit::TestCase
  test "every method runs inside a Ractor" do
    port = Ractor::Port.new
    ractor = Ractor.new(port) do |out|
      out << [
        AVFoundationMac.devices.class,
        AVFoundationMac.snapshot("no-such-device", "/nonexistent/x.jpg", format: :heic),
        AVFoundationMac.open_session("no-such-device"),
        AVFoundationMac.capture_frame("/nonexistent/x.jpg"),
        AVFoundationMac.close_session
      ]
    end
    ractor.join
    assert_equal([String, "", "", "", nil], port.receive)
  end

  test "argument errors raised inside a Ractor reach the caller" do
    port = Ractor::Port.new
    ractor = Ractor.new(port) do |out|
      AVFoundationMac.snapshot("no-such-device", "/nonexistent/x.jpg", format: :png)
    rescue ArgumentError => e
      out << e.class
    end
    ractor.join
    assert_equal(ArgumentError, port.receive)
  end
end
