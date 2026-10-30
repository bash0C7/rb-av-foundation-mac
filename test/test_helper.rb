# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "av_foundation_mac"

require "test-unit"

module CameraGate
  def camera_device_id
    id = ENV.fetch("AV_FOUNDATION_MAC_TEST_DEVICE", "")
    omit "Set AV_FOUNDATION_MAC_TEST_DEVICE to a camera id from AVFoundationMac.devices to run capture tests" if id.empty?
    ids = AVFoundationMac.devices.lines.map { |line| line.split("\t").first }
    omit "AV_FOUNDATION_MAC_TEST_DEVICE is not connected" unless ids.include?(id)
    id
  end

  def image_size(path)
    out = IO.popen(["sips", "-g", "pixelWidth", "-g", "pixelHeight", path], &:read)
    [out[/pixelWidth: (\d+)/, 1].to_i, out[/pixelHeight: (\d+)/, 1].to_i]
  end
end
