// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "KinemaPlugins",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
        .tvOS(.v17)
    ],
    products: [
        .library(name: "KinemaPlugins", targets: ["KinemaPlugins"])
    ],
    dependencies: [
        .package(path: "../KinemaCore"),
        .package(path: "../KinemaPlayback")
    ],
    targets: [
        .target(name: "KinemaPlugins", dependencies: ["KinemaCore", "KinemaPlayback"])
    ]
)
