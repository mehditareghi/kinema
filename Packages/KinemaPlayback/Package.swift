// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "KinemaPlayback",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
        .tvOS(.v17)
    ],
    products: [
        .library(name: "KinemaPlayback", targets: ["KinemaPlayback"])
    ],
    dependencies: [
        .package(path: "../KinemaCore"),
        .package(path: "../KinemaMPV"),
        .package(path: "../KinemaMedia"),
        .package(path: "../KinemaSubtitles")
    ],
    targets: [
        .target(
            name: "KinemaPlayback",
            dependencies: ["KinemaCore", "KinemaMPV", "KinemaMedia", "KinemaSubtitles"]
        )
    ]
)
