import AVFoundation

let devices = AVCaptureDevice.DiscoverySession(
    deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera, .deskViewCamera],
    mediaType: .video,
    position: .unspecified
).devices

for device in devices {
    print([device.uniqueID, device.localizedName, device.deviceType.rawValue].joined(separator: "\t"))
}
