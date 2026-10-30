// swift-tools-version: 6.4

import PackageDescription

let package = Package(
    name: "AVFoundationMac",
    platforms: [.macOS(.v27)],
    products: [
        .library(
            name: "AVFoundationMac",
            type: .dynamic,
            targets: ["AVFoundationMac"]
        ),
    ],
    targets: [
        .target(
            name: "AVFoundationMac"
        ),
    ]
)
