import Foundation

private func token(_ cancel: UnsafeMutableRawPointer) -> CancelToken {
    Unmanaged<CancelToken>.fromOpaque(cancel).takeUnretainedValue()
}

/// Calls `devices()` from C as `av_foundation_mac_devices`.
///
/// The returned buffer is allocated with `strdup`. Release it with ``cFree(_:)``.
///
/// - Returns: A newly allocated NUL-terminated UTF-8 string owned by the caller.
@c(av_foundation_mac_devices)
public func cDevices() -> UnsafeMutablePointer<CChar> {
    strdup(devices())!
}

/// Creates a cancellation token for one blocking call, exposed to C as `av_foundation_mac_cancel_new`.
///
/// - Returns: A token to pass to ``cSnapshot(_:_:_:_:_:_:_:)`` or ``cOpenSession(_:_:_:_:_:_:)``. Release it with ``cCancelFree(_:)``.
@c(av_foundation_mac_cancel_new)
public func cCancelNew() -> UnsafeMutableRawPointer {
    Unmanaged.passRetained(CancelToken()).toOpaque()
}

/// Makes the blocking call that holds `cancel` return now, exposed to C as `av_foundation_mac_cancel`.
///
/// Safe to call from any thread, any number of times.
///
/// - Parameter cancel: A token from ``cCancelNew()``.
@c(av_foundation_mac_cancel)
public func cCancel(_ cancel: UnsafeMutableRawPointer) {
    token(cancel).cancel()
}

/// Releases a token from ``cCancelNew()``, exposed to C as `av_foundation_mac_cancel_free`.
///
/// - Parameter cancel: A token no call uses any more.
@c(av_foundation_mac_cancel_free)
public func cCancelFree(_ cancel: UnsafeMutableRawPointer) {
    Unmanaged<CancelToken>.fromOpaque(cancel).release()
}

/// Calls `snapshot(deviceID:path:settings:cancel:)` from C as `av_foundation_mac_snapshot`.
///
/// The returned buffer is allocated with `strdup`. Release it with ``cFree(_:)``.
///
/// - Parameters:
///   - deviceID: A NUL-terminated UTF-8 device `uniqueID`.
///   - path: A NUL-terminated UTF-8 output path.
///   - format: `jpeg` or `heic`.
///   - width: The width of the fitting box, or `0`.
///   - height: The height of the fitting box, or `0`.
///   - quality: The lossy compression quality.
///   - cancel: A token from ``cCancelNew()``.
/// - Returns: A newly allocated NUL-terminated UTF-8 string owned by the caller.
@c(av_foundation_mac_snapshot)
public func cSnapshot(
    _ deviceID: UnsafePointer<CChar>,
    _ path: UnsafePointer<CChar>,
    _ format: UnsafePointer<CChar>,
    _ width: Int,
    _ height: Int,
    _ quality: Double,
    _ cancel: UnsafeMutableRawPointer
) -> UnsafeMutablePointer<CChar> {
    let settings = EncodeSettings(format: String(cString: format), width: width, height: height, quality: quality)
    let result = snapshot(deviceID: String(cString: deviceID), path: String(cString: path), settings: settings, cancel: token(cancel))
    return strdup(result)!
}

/// Calls `openSession(deviceID:settings:cancel:)` from C as `av_foundation_mac_open_session`.
///
/// The returned buffer is allocated with `strdup`. Release it with ``cFree(_:)``.
///
/// - Parameters:
///   - deviceID: A NUL-terminated UTF-8 device `uniqueID`.
///   - format: `jpeg` or `heic`.
///   - width: The width of the fitting box, or `0`.
///   - height: The height of the fitting box, or `0`.
///   - quality: The lossy compression quality.
///   - cancel: A token from ``cCancelNew()``.
/// - Returns: A newly allocated NUL-terminated UTF-8 string owned by the caller.
@c(av_foundation_mac_open_session)
public func cOpenSession(
    _ deviceID: UnsafePointer<CChar>,
    _ format: UnsafePointer<CChar>,
    _ width: Int,
    _ height: Int,
    _ quality: Double,
    _ cancel: UnsafeMutableRawPointer
) -> UnsafeMutablePointer<CChar> {
    let settings = EncodeSettings(format: String(cString: format), width: width, height: height, quality: quality)
    return strdup(openSession(deviceID: String(cString: deviceID), settings: settings, cancel: token(cancel)))!
}

/// Calls `captureFrame(path:)` from C as `av_foundation_mac_capture_frame`.
///
/// The returned buffer is allocated with `strdup`. Release it with ``cFree(_:)``.
///
/// - Parameter path: A NUL-terminated UTF-8 output path.
/// - Returns: A newly allocated NUL-terminated UTF-8 string owned by the caller.
@c(av_foundation_mac_capture_frame)
public func cCaptureFrame(_ path: UnsafePointer<CChar>) -> UnsafeMutablePointer<CChar> {
    strdup(captureFrame(path: String(cString: path)))!
}

/// Calls `closeSession()` from C as `av_foundation_mac_close_session`.
@c(av_foundation_mac_close_session)
public func cCloseSession() {
    closeSession()
}

/// Releases a buffer returned by a bridge function, exposed to C as `av_foundation_mac_free`.
///
/// The caller owns every returned buffer and must pass it to this function exactly once.
///
/// - Parameter ptr: The buffer to release, or `nil`.
@c(av_foundation_mac_free)
public func cFree(_ ptr: UnsafeMutablePointer<CChar>?) {
    free(ptr)
}
