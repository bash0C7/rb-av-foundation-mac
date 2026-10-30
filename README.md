# rb-av-foundation-mac

Ruby binding for Apple's AVFoundation camera capture on macOS / Apple Silicon. Enumerates cameras, including Continuity Camera and Desk View, and writes frames to JPEG or HEIC files, through Swift Package Manager and a thin C bridge. Built on [swift_gem](https://github.com/bash0C7/swift_gem).

## Requirements

- macOS 27+, Apple Silicon
- Xcode 27 (builds run `xcrun swift`)
- Ruby 4.0+, Bundler 4.x

## Installation

Install from source:

```bash
git clone https://github.com/bash0C7/rb-av-foundation-mac.git
cd rb-av-foundation-mac
bundle install
bundle exec rake compile
```

## Camera permission

The first `snapshot` or `open_session` makes macOS ask whether the app that started Ruby (Terminal, iTerm, the VS Code terminal, ...) may use the camera. Until it is allowed, both return `""`. To allow it later: System Settings → Privacy & Security → Camera → turn the app on. `devices` needs no permission.

## Usage

### List cameras

```ruby
require "av_foundation_mac"

AVFoundationMac.devices
# => "<id>\tFaceTime HD Camera\tunspecified\n<id>\tiPhone Camera\tunspecified"
```

One `id\tname\tposition` line per camera. `position` is `front`, `back`, or `unspecified`; built-in, USB, and Continuity cameras on a Mac report `unspecified`. Pass the `id` to `snapshot` or `open_session`.

### One frame

```ruby
AVFoundationMac.snapshot(id, "/tmp/out.jpg")
# => "/tmp/out.jpg", or "" on failure

AVFoundationMac.snapshot(id, "/tmp/out.heic", format: :heic, width: 640, height: 480, quality: 0.7)
```

`snapshot` starts the camera, waits two seconds for auto-exposure to settle, writes one frame, and stops the camera. It returns `""` when the camera is missing, busy, or not permitted, when no frame arrives within ten seconds, or when the file cannot be written. The parent directory of the output path must exist.

### Repeated frames

```ruby
AVFoundationMac.open_session(id, format: :heic, width: 1280, height: 720)
# => "ok", or "" on failure

AVFoundationMac.capture_frame("/tmp/frame1.heic")  # => "/tmp/frame1.heic"
AVFoundationMac.capture_frame("/tmp/frame2.heic")  # => "/tmp/frame2.heic"

AVFoundationMac.close_session                       # => nil
```

`open_session` keeps the camera running so each `capture_frame` writes the newest frame at once, with the settings given to `open_session`. A Continuity Camera iPhone shows its connection prompt once per session, not once per frame. A process has at most one session: `open_session` closes the open one first, and leaves none open when it fails. `capture_frame` returns `""` when no session is open. `close_session` does nothing when no session is open.

### Options

| Keyword | Default | Values |
|---|---|---|
| `format:` | `:jpeg` | `:jpeg`, `:heic` |
| `width:` | `0` | With `height:`, the box the frame is fitted into |
| `height:` | `0` | With `width:`, the box the frame is fitted into |
| `quality:` | `0.85` | Lossy compression quality, `0.0` to `1.0` |

When `width` and `height` are both positive, the frame is scaled to fit inside the box with its aspect ratio kept: a 1920×1080 frame in a 640×480 box becomes 640×360. An unknown format or keyword raises `ArgumentError`.

### Threads, interrupts, and Ractors

`snapshot`, `open_session`, `capture_frame`, and `close_session` release the GVL, so other threads run while `snapshot` and `open_session` wait for the camera. `Interrupt` (Ctrl-C), `Thread#raise`, and `Thread#kill` end that wait at once; an `open_session` interrupted during the warm-up leaves no session open. An interrupt that raises nothing, such as a `trap` handler that returns or `Thread#wakeup`, also ends the wait, and the call returns `""`.

All methods run inside a Ractor. The one session is shared by every thread and Ractor in the process.

## Examples

```bash
bundle exec ruby examples/snapshot.rb                       # lists cameras
bundle exec ruby examples/snapshot.rb <id> /tmp/out.jpg     # writes one frame
xcrun swift examples/av_foundation_mac.swift                # lists cameras with their device types, without Ruby
```

`bundle exec rake console` opens IRB with the gem loaded.

## Development

```bash
bundle install
bundle exec rake test
AV_FOUNDATION_MAC_TEST_DEVICE=<id> bundle exec rake test
```

`rake test` validates `sig/av_foundation_mac.rbs`, runs `xcrun swift build -c release --package-path ext/av_foundation_mac`, builds the C extension into `lib/av_foundation_mac/av_foundation_mac.bundle`, then runs the tests. The tests that use a camera run only when `AV_FOUNDATION_MAC_TEST_DEVICE` names a connected camera id from `AVFoundationMac.devices` and the terminal has camera permission; they use only that camera and write into temporary directories they delete.

## License

MIT
