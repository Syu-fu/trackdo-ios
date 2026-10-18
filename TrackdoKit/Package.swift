// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "TrackdoKit",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "TrackdoKit", targets: ["TrackdoKit"]),
    ],
    targets: [
        // Built by scripts/build-xcframework.sh from crates/trackdo-ffi.
        .binaryTarget(name: "TrackdoFFIC", path: "TrackdoFFIC.xcframework"),
        .target(name: "TrackdoFFI", dependencies: ["TrackdoFFIC"]),
        .target(name: "TrackdoKit", dependencies: ["TrackdoFFI"]),
        .testTarget(name: "TrackdoFFITests", dependencies: ["TrackdoFFI"]),
        .testTarget(name: "TrackdoKitTests", dependencies: ["TrackdoKit"]),
    ]
)
