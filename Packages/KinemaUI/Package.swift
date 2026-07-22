// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "KinemaUI",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
        .tvOS(.v17)
    ],
    products: [
        .library(name: "KinemaUI", targets: ["KinemaUI"])
    ],
    dependencies: [
        .package(path: "../KinemaCore"),
        .package(path: "../KinemaMedia"),
        .package(path: "../KinemaPlayback"),
        .package(path: "../KinemaSubtitles")
    ],
    targets: [
        .target(
            name: "KinemaUI",
            dependencies: ["KinemaCore", "KinemaMedia", "KinemaPlayback", "KinemaSubtitles"],
            linkerSettings: [
                .linkedFramework("AVFoundation"),
                .linkedFramework("QuickLookThumbnailing"),
                .linkedFramework("IOKit", .when(platforms: [.macOS]))
            ]
        )
    ]
)
