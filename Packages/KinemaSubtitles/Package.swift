// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "KinemaSubtitles",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
        .tvOS(.v17)
    ],
    products: [
        .library(name: "KinemaSubtitles", targets: ["KinemaSubtitles"])
    ],
    dependencies: [
        .package(path: "../KinemaCore")
    ],
    targets: [
        .target(name: "KinemaSubtitles", dependencies: ["KinemaCore"])
    ]
)
