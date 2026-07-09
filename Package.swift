// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "BlastRadius",
    platforms: [
        .iOS(.v13),
        .macOS(.v10_15),
        .tvOS(.v13),
        .watchOS(.v6),
        .visionOS(.v1)
    ],
    products: [
        .library(name: "BlastRadius", targets: ["BlastRadius"]),
    ],
    targets: [
        .target(name: "BlastRadius", path: "Sources"),
        .testTarget(name: "BlastRadiusTests", dependencies: ["BlastRadius"], path: "Tests"),
    ]
)
