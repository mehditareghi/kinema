// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "KinemaMedia",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
        .tvOS(.v17)
    ],
    products: [
        .library(name: "KinemaMedia", targets: ["KinemaMedia"])
    ],
    dependencies: [
        .package(path: "../KinemaCore"),
        .package(path: "../KinemaMPV"),
        .package(path: "../MPVKitVendor")
    ],
    targets: [
        .target(
            name: "KinemaMedia",
            dependencies: [
                "KinemaCore",
                "KinemaMPV",
                .product(name: "FFmpegKit", package: "MPVKitVendor")
            ]
        )
    ]
)
