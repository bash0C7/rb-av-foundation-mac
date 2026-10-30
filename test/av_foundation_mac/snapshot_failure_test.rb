# frozen_string_literal: true

require "test_helper"
require "tmpdir"

class AVFoundationMacSnapshotFailureTest < Test::Unit::TestCase
  test "snapshot returns empty string for nonexistent device_id" do
    Dir.mktmpdir do |dir|
      out = File.join(dir, "should_not_exist.jpg")
      result = AVFoundationMac.snapshot("definitely-not-a-real-device-id", out)
      assert_equal("", result)
      assert_false(File.exist?(out), "No file should be written on failure")
    end
  end

  test "snapshot accepts 2 string args without raising" do
    Dir.mktmpdir do |dir|
      out = File.join(dir, "x.jpg")
      assert_nothing_raised do
        AVFoundationMac.snapshot("nope", out)
      end
    end
  end
end
