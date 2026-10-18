// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "TrackdoKit",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "TrackdoFFI", targets: ["TrackdoFFI"]),
    ],
    targets: [
        // Built by scripts/build-xcframework.sh from crates/trackdo-ffi.
        .binaryTarget(name: "TrackdoFFIC", path: "TrackdoFFIC.xcframework"),
        .target(name: "TrackdoFFI", dependencies: ["TrackdoFFIC"]),
        .testTarget(name: "TrackdoFFITests", dependencies: ["TrackdoFFI"]),
    ]
)
