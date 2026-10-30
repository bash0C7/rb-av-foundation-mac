#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../lib/av_foundation_mac"

device_id, out_path = ARGV
unless device_id && out_path
  warn "usage: bundle exec ruby examples/snapshot.rb DEVICE_ID OUT_PATH"
  warn ""
  warn AVFoundationMac.devices
  exit 1
end

result = AVFoundationMac.snapshot(device_id, out_path)
abort "snapshot failed" if result.empty?
puts "wrote #{result} (#{File.size(result)} bytes)"
