// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "BrassTuneCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "BrassTuneCore", targets: ["BrassTuneCore"])
    ],
    targets: [
        .target(name: "BrassTuneCore"),
        .testTarget(name: "BrassTuneCoreTests", dependencies: ["BrassTuneCore"])
    ]
)
