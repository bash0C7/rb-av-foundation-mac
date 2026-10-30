import AVFoundation
import CoreImage
import Foundation
import ImageIO
import Synchronization
import UniformTypeIdentifiers

private let frameTimeout: DispatchTimeInterval = .seconds(10)

private let warmupDuration: DispatchTimeInterval = .seconds(2)

private let cameraDeviceTypes: [AVCaptureDevice.DeviceType] = [
    .builtInWideAngleCamera,
    .external,
    .continuityCamera,
    .deskViewCamera,
]

private let ciContext = CIContext()

private func discoverDevices() -> [AVCaptureDevice] {
    AVCaptureDevice.DiscoverySession(
        deviceTypes: cameraDeviceTypes,
        mediaType: .video,
        position: .unspecified
    ).devices
}

/// Lists the video capture devices of the types in `cameraDeviceTypes`.
///
/// ``cDevices()`` exposes this function to C.
///
/// - Returns: One `id\tname\tposition` line per device, where `position` is `front`, `back`, or `unspecified`.
func devices() -> String {
    discoverDevices()
        .map { device in
            let position = switch device.position {
            case .front: "front"
            case .back: "back"
            default: "unspecified"
            }
            let name = device.localizedName.replacing("\t", with: " ")
            return "\(device.uniqueID)\t\(name)\t\(position)"
        }
        .joined(separator: "\n")
}

/// How a captured frame is written to a file.
struct EncodeSettings: Sendable {
    /// The image container: `public.jpeg` or `public.heic`.
    let type: UTType
    /// The width of the box the frame is fitted into, or `0` to keep the frame size.
    let width: Int
    /// The height of the box the frame is fitted into, or `0` to keep the frame size.
    let height: Int
    /// The lossy compression quality from `0.0` to `1.0`.
    let quality: Double

    /// Creates settings from the values passed by Ruby.
    ///
    /// - Parameters:
    ///   - format: `heic` for HEIC; any other value selects JPEG.
    ///   - width: The width of the fitting box.
    ///   - height: The height of the fitting box.
    ///   - quality: The lossy compression quality.
    init(format: String, width: Int, height: Int, quality: Double) {
        self.type = format == "heic" ? .heic : .jpeg
        self.width = width
        self.height = height
        self.quality = quality
    }
}

private func encode(_ pixelBuffer: CVPixelBuffer, to path: String, with settings: EncodeSettings) -> String {
    var image = CIImage(cvPixelBuffer: pixelBuffer)
    if settings.width > 0 && settings.height > 0 {
        let scale = min(Double(settings.width) / image.extent.width, Double(settings.height) / image.extent.height)
        image = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
    }
    guard
        let cgImage = ciContext.createCGImage(image, from: image.extent.integral),
        let destination = CGImageDestinationCreateWithURL(
            URL(filePath: path) as CFURL, settings.type.identifier as CFString, 1, nil
        )
    else { return "" }
    let options = [kCGImageDestinationLossyCompressionQuality: settings.quality] as CFDictionary
    CGImageDestinationAddImage(destination, cgImage, options)
    return CGImageDestinationFinalize(destination) ? path : ""
}

/// A cancellation token for one blocking call from Ruby.
///
/// ``cancel()`` makes the wait in progress, and every later wait, end as `.timedOut`.
final class CancelToken: Sendable {
    private let state = Mutex<(cancelled: Bool, waiting: DispatchSemaphore?)>((false, nil))

    /// Ends the current and all later ``wait(_:until:)`` calls. Only the first call signals the waited semaphore.
    func cancel() {
        let waiting = state.withLock { s -> DispatchSemaphore? in
            if s.cancelled { return nil }
            s.cancelled = true
            return s.waiting
        }
        waiting?.signal()
    }

    /// Waits on `semaphore` until `deadline` or until ``cancel()``.
    ///
    /// - Parameters:
    ///   - semaphore: The semaphore a capture callback signals.
    ///   - deadline: The time at which the wait times out.
    /// - Returns: `.success` when `semaphore` was signaled, `.timedOut` on the deadline or after ``cancel()``.
    func wait(_ semaphore: DispatchSemaphore, until deadline: DispatchTime) -> DispatchTimeoutResult {
        let cancelled = state.withLock { s in
            s.waiting = semaphore
            return s.cancelled
        }
        let result = cancelled ? .timedOut : semaphore.wait(timeout: deadline)
        return state.withLock { s in
            s.waiting = nil
            return s.cancelled ? .timedOut : result
        }
    }
}

/// Keeps the newest frame from an `AVCaptureVideoDataOutput` and reports when the camera has settled.
///
/// The first frames after `startRunning()` come before auto-exposure, auto-white-balance, and gain converge,
/// so they are near-black. The warm-up starts at ``startWarmup()``, after `startRunning()` returns,
/// and the camera counts as settled at the first frame after it ends.
private final class FrameReceiver: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, Sendable {
    private let settledSignal = DispatchSemaphore(value: 0)
    private let deadline = DispatchTime.now() + frameTimeout
    private let state = Mutex<(latest: CVPixelBuffer?, warmupEnd: DispatchTime?, settled: Bool)>((nil, nil, false))

    /// Starts the warm-up. Frames delivered before this call never settle the camera.
    func startWarmup() {
        state.withLock { $0.warmupEnd = DispatchTime.now() + warmupDuration }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = sampleBuffer.imageBuffer else { return }
        let now = DispatchTime.now()
        let first = state.withLock { s in
            s.latest = pixelBuffer
            guard let warmupEnd = s.warmupEnd, now >= warmupEnd, !s.settled else { return false }
            s.settled = true
            return true
        }
        if first { settledSignal.signal() }
    }

    /// Waits until the camera settles, `frameTimeout` after this receiver was created, or ``CancelToken/cancel()``.
    ///
    /// - Parameter cancel: The token that ends the wait.
    /// - Returns: `true` when the camera settled.
    func waitUntilSettled(cancel: CancelToken) -> Bool {
        cancel.wait(settledSignal, until: deadline) == .success
    }

    /// Writes the newest frame to `path` once the camera has settled.
    ///
    /// - Parameters:
    ///   - path: The output file path.
    ///   - settings: The container, size, and quality.
    /// - Returns: `path`, or an empty string before the camera settles or when the file cannot be written.
    func writeLatest(to path: String, with settings: EncodeSettings) -> String {
        state.withLock { s in
            guard s.settled, let latest = s.latest else { return "" }
            return encode(latest, to: path, with: settings)
        }
    }
}

/// A running `AVCaptureSession` with one device input and one video data output feeding a ``FrameReceiver``.
private final class Capture {
    let receiver = FrameReceiver()
    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "av_foundation_mac.frames")

    /// Starts a session on the device `deviceID`.
    ///
    /// - Parameter deviceID: The `uniqueID` of the device.
    /// - Returns: `nil` when the device is missing or cannot be added to a session.
    init?(deviceID: String) {
        guard
            let device = discoverDevices().first(where: { $0.uniqueID == deviceID }),
            let input = try? AVCaptureDeviceInput(device: device),
            session.canAddInput(input)
        else { return nil }
        session.sessionPreset = .high
        session.addInput(input)
        let output = AVCaptureVideoDataOutput()
        output.setSampleBufferDelegate(receiver, queue: queue)
        guard session.canAddOutput(output) else { return nil }
        session.addOutput(output)
        session.startRunning()
        receiver.startWarmup()
    }

    /// Stops the session synchronously.
    func stop() {
        session.stopRunning()
    }
}

/// Opens a session on the device `deviceID`, writes one settled frame to `path`, and closes the session.
///
/// ``cSnapshot(_:_:_:_:_:_:_:)`` exposes this function to C.
///
/// - Parameters:
///   - deviceID: The `uniqueID` of the device.
///   - path: The output file path. Its parent directory must exist.
///   - settings: The container, size, and quality.
///   - cancel: The token that ends the wait for the camera.
/// - Returns: `path`, or an empty string when no settled frame arrives, the wait is cancelled, or the file cannot be written.
func snapshot(deviceID: String, path: String, settings: EncodeSettings, cancel: CancelToken) -> String {
    guard let capture = Capture(deviceID: deviceID) else { return "" }
    defer { capture.stop() }
    guard capture.receiver.waitUntilSettled(cancel: cancel) else { return "" }
    return capture.receiver.writeLatest(to: path, with: settings)
}

private struct OpenSession {
    let capture: Capture
    let settings: EncodeSettings
}

private let openSession = Mutex<OpenSession?>(nil)

/// Opens the persistent session on the device `deviceID`, closing the session already open first.
///
/// The session is published before the warm-up so ``closeSession()`` can stop it; ``captureFrame(path:)`` writes nothing until it settles.
/// ``cOpenSession(_:_:_:_:_:_:)`` exposes this function to C.
///
/// - Parameters:
///   - deviceID: The `uniqueID` of the device.
///   - settings: The container, size, and quality used by every ``captureFrame(path:)``.
///   - cancel: The token that ends the wait for the camera.
/// - Returns: `ok`, or an empty string when the session cannot start or settle. This call leaves no session of its own open after a failure.
func openSession(deviceID: String, settings: EncodeSettings, cancel: CancelToken) -> String {
    let receiver = openSession.withLock { slot -> FrameReceiver? in
        slot?.capture.stop()
        slot = nil
        guard let capture = Capture(deviceID: deviceID) else { return nil }
        slot = OpenSession(capture: capture, settings: settings)
        return capture.receiver
    }
    guard let receiver else { return "" }
    if receiver.waitUntilSettled(cancel: cancel) { return "ok" }
    openSession.withLock { slot in
        guard slot?.capture.receiver === receiver else { return }
        slot?.capture.stop()
        slot = nil
    }
    return ""
}

/// Writes the newest frame of the persistent session to `path`.
///
/// ``cCaptureFrame(_:)`` exposes this function to C.
///
/// - Parameter path: The output file path.
/// - Returns: `path`, or an empty string when no settled session is open or the file cannot be written.
func captureFrame(path: String) -> String {
    let current = openSession.withLock { slot in
        slot.map { (receiver: $0.capture.receiver, settings: $0.settings) }
    }
    guard let current else { return "" }
    return current.receiver.writeLatest(to: path, with: current.settings)
}

/// Stops and releases the persistent session. Does nothing when none is open.
///
/// ``cCloseSession()`` exposes this function to C.
func closeSession() {
    openSession.withLock { slot in
        slot?.capture.stop()
        slot = nil
    }
}
