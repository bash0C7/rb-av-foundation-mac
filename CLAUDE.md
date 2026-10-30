# CLAUDE.md — rb-av-foundation-mac

## Position

Ruby native binding for Apple's AVFoundation camera capture on macOS, built on the `bash0C7/swift_gem` scaffold. Enumerates cameras and writes frames to JPEG or HEIC, as one-shot snapshots or from one persistent session. Sibling of `rb-vision-mac` (static-image analysis), which consumes the files this gem writes. `camera-daemon` is the consumer of the persistent session.

## Core design principles

1. Thin wrapper over `AVCaptureSession` + `AVCaptureVideoDataOutput`. `snapshot` is one frame → one file. The persistent session (`open_session` / `capture_frame` / `close_session`) keeps the device running, because a Continuity Camera iPhone prompts once per session start. At most one session per process.
2. Fixed defaults: JPEG, quality 0.85, native size, a 2s auto-exposure warm-up, a 10s frame timeout counted from session creation. Devices enumerate `.builtInWideAngleCamera`, `.external`, `.continuityCamera`, `.deskViewCamera`.
3. AVFoundation-side failure (missing or busy device, no permission, timeout, write error) → empty string, no exception. Argument errors at the Ruby boundary raise: `rb_get_kwargs` rejects unknown keywords, `format:` must be the Symbol `:jpeg` or `:heic`.
4. C bridge string handoff via `@c(av_foundation_mac_*)` (SE-0495). Every returned buffer is released with `av_foundation_mac_free`.
5. Scaffold parity. `bundle exec rake "new[rb-av-foundation-mac,<dir>]"` in swift_gem produces a skeleton whose only diffs against this repo are the module and package name (the generator emits `AvFoundationMac`; this gem keeps Apple's `AVFoundationMac` casing), the implementation body, `sig/`, examples, tests and `test_helper.rb`'s `CameraGate`, docs, gemspec summary and description, the `docs/superpowers/` and `HANDOFF.md` lines in `.gitignore`, and build artifacts.

## Architecture

```
[caller (Ruby)]
  │   AVFoundationMac.{devices, snapshot, open_session, capture_frame, close_session}
  ▼
lib/av_foundation_mac.rb                          ← requires the ext + module declaration
  ▼
ext/av_foundation_mac/av_foundation_mac.c          ← kwargs parsing, rb_thread_call_without_gvl + cancel ubf
  ▼
Sources/AVFoundationMac/AVFoundationMacBridge.swift   ← @c(av_foundation_mac_*) exports, CancelToken handles
  ▼
Sources/AVFoundationMac/AVFoundationMac.swift          ← Capture, FrameReceiver, the session Mutex, CIImage → ImageIO encode
  ▼
[Apple AVFoundation framework]
```

## Public API

| Method | Returns | Notes |
|---|---|---|
| `devices` | newline-separated `"id\tname\tposition"` | `position` ∈ {front, back, unspecified}; Mac cameras report `unspecified` |
| `snapshot(device_id, out_path, format: :jpeg, width: 0, height: 0, quality: 0.85)` | `out_path` or `""` | Starts a session, waits for a settled frame, encodes, stops. Caller creates the parent directory |
| `open_session(device_id, **same kwargs)` | `"ok"` or `""` | Closes the open session, starts a new one, waits for it to settle. A failed or interrupted open leaves no session of its own |
| `capture_frame(out_path)` | `out_path` or `""` | Encodes the newest frame of the open session with its settings; `""` with no session or before it settles |
| `close_session` | `nil` | Idempotent |

Signatures and their documentation live in `sig/av_foundation_mac.rbs`.

## Concurrency model

- `FrameReceiver` (the `AVCaptureVideoDataOutputSampleBufferDelegate`) is a `Sendable` final class. Its newest `CVPixelBuffer` and settled flag live in a `Mutex`; encoding runs inside that lock so the buffer never leaves it. The settled `DispatchSemaphore` is signaled once, for the first frame after the warm-up.
- The persistent session is `Mutex<OpenSession?>`. `open_session` creates and starts the `Capture` inside the lock and publishes it before the warm-up, then waits outside the lock on the `Sendable` receiver; on failure it stops the session only if the slot still holds its own receiver. `close_session` and a later `open_session` can therefore stop a warming session. `capture_frame` copies the receiver and settings out of the lock and encodes outside it.
- The warm-up clock starts when `startRunning()` returns (`FrameReceiver.startWarmup()`), so a slow device start cannot skip it. The 10s deadline is fixed when the receiver is created.
- A warming `open_session` whose session another thread stops gets no more frames and returns `""` at its deadline. `close_session` and `capture_frame` wait on the session `Mutex` while another thread is inside `startRunning()`; `close_session` has no ubf, so an interrupt reaches it only after that.
- `AVCaptureSession` is not `Sendable`, so `Capture` stays non-`Sendable` and never leaves the `Mutex` region. No `@unchecked Sendable`, no `nonisolated(unsafe)`.
- Blocking calls run under `rb_thread_call_without_gvl` with `av_foundation_mac_cancel` as the ubf. Waits go through `CancelToken.wait(_:until:)`, so Interrupt, `Thread#raise`, and `Thread#kill` end them at once; an interrupt that raises nothing also cancels the token and the call returns `""`. String arguments are converted and copied with `rb_str_new_frozen` before the GVL is released, so a caller mutating them cannot free the bytes Swift reads. `rb_protect` frees the token and result buffer when the interrupt unwinds. `startRunning()` / `stopRunning()` are synchronous AVFoundation calls and are not cancellable.
- `Init_av_foundation_mac` calls `rb_ext_ractor_safe(true)`. The C layer holds no Ruby state besides the keyword `ID`s set in `Init`.

## Build flow

`bundle exec rake test` validates the RBS, builds, and tests in one shot. `xcrun swift build -c release --package-path ext/av_foundation_mac` writes `AVFoundationMac-Swift.h` under `ext/av_foundation_mac/.build/out/Intermediates.noindex/GeneratedModuleMaps/` (added with `-I`) and the dylib under `ext/av_foundation_mac/.build/release`. The extension Makefile does not track that header, so a changed `@c` signature reaches the C side only after `rake clobber compile` or an edit to `av_foundation_mac.c`.

## Tests

Tests without a camera cover argument validation, the no-session paths, `close_session` idempotence, concurrent open/close, and every method inside a Ractor. `camera_test.rb` runs only when `AV_FOUNDATION_MAC_TEST_DEVICE` names a connected camera id, and uses only that camera. Use the built-in camera's id so the tests never wake a Continuity Camera iPhone; `xcrun swift examples/av_foundation_mac.swift` shows each id with its device type. Captured files go to `Dir.mktmpdir` and are checked by magic bytes and `sips` pixel size only.

## Usage / why no CLI

Library only. Interactive checks via `bundle exec rake console`. `examples/snapshot.rb` takes a device id and an output path; `examples/av_foundation_mac.swift` lists cameras without Ruby.

## Related projects

- `~/dev/src/github.com/bash0C7/swift_gem` — scaffold/Mkmf framework
- `~/dev/src/github.com/bash0C7/rb-vision-mac` — static-image Vision sibling
- `~/dev/src/github.com/bash0C7/camera-daemon` — persistent-session consumer; parses `devices` as three tab-separated fields

## Environment requirements

macOS 27+, Apple Silicon, Xcode 27 (Swift 6.4, builds run `xcrun swift`), Ruby 4.0+, bundler 4.x, rake-compiler 1.2+. Gems install into `vendor/bundle` (`.bundle/config`). `Gemfile.lock` is not git-tracked.

## Prohibitions

- No Python source
- No code comments. Swift is documented with DocC (`///`, `- Parameter`, `- Returns`, ``` ``symbol`` ``` links); Ruby is documented with `#` comments above declarations in `sig/av_foundation_mac.rbs`. History goes in commit messages
- Do not hand-edit `ext/av_foundation_mac/swift_mkmf.rb`; re-copy it from swift_gem
- Do not git-track `Gemfile.lock`, `docs/superpowers/`, or `HANDOFF.md`
- Do not add crop / rotate (consumer responsibility); resize and HEIC stay because they sit on the encode path the gem owns
- Do not automate the TCC camera grant
- Do not let tests pick a camera on their own; they use only `AV_FOUNDATION_MAC_TEST_DEVICE`
- Do not commit captured images
- Commit messages in English, conventional commits style
- `.claude/` is committed
