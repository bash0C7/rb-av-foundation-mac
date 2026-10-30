# frozen_string_literal: true

require "test_helper"

class AVFoundationMacDevicesTest < Test::Unit::TestCase
  test "devices returns a String" do
    output = AVFoundationMac.devices
    assert_kind_of(String, output)
  end

  test "devices output contains at least one line on a Mac with built-in camera" do
    output = AVFoundationMac.devices
    assert_false(output.strip.empty?, "Expected at least one device, got empty string")
  end

  test "each devices line has exactly 3 tab-separated fields" do
    output = AVFoundationMac.devices
    output.split("\n").each do |line|
      parts = line.split("\t")
      assert_equal(3, parts.length, "Expected 3 tab-separated fields, got: #{line.inspect}")
      parts.each { |p| assert_false(p.empty?, "Empty field in line: #{line.inspect}") }
    end
  end

  test "position field is one of front/back/unspecified" do
    valid = %w[front back unspecified]
    output = AVFoundationMac.devices
    output.split("\n").each do |line|
      pos = line.split("\t").last
      assert_include(valid, pos, "Unexpected position: #{pos.inspect} in #{line.inspect}")
    end
  end
end
