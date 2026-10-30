# frozen_string_literal: true

require_relative "swift_mkmf"

SwiftGem::Mkmf.create_swift_makefile(
  "av_foundation_mac/av_foundation_mac",
  package: "AVFoundationMac",
  source_dir: __dir__
)
