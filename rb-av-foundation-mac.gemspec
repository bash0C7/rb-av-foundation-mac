# frozen_string_literal: true

require_relative "lib/av_foundation_mac/version"

Gem::Specification.new do |spec|
  spec.name = "rb-av-foundation-mac"
  spec.version = AVFoundationMac::VERSION
  spec.authors = ["bash0C7"]
  spec.email = ["ksb.4038.nullpointer+github@gmail.com"]

  spec.summary = "Native Apple AVFoundation camera capture for Ruby on macOS"
  spec.description = "Enumerates cameras and captures frames to JPEG or HEIC files through Apple's AVFoundation framework, including Continuity Camera, as one-shot snapshots or from a persistent capture session. Built on swift_gem."
  spec.homepage = "https://github.com/bash0C7/rb-av-foundation-mac"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 4.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/bash0C7/rb-av-foundation-mac"

  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ Gemfile .gitignore test/ .github/])
    end
  end
  spec.require_paths = ["lib"]
  spec.extensions = ["ext/av_foundation_mac/extconf.rb"]
end
