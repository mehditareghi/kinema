// swift-tools-version: 5.9
import PackageDescription

/// Workspace manifest — open Kinema.xcworkspace in Xcode for app targets.
/// Individual packages under Packages/ can also be opened independently.
let package = Package(
    name: "KinemaWorkspace",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
        .tvOS(.v17)
    ],
    products: [],
    dependencies: [
        .package(path: "Packages/KinemaCore"),
        .package(path: "Packages/KinemaMPV"),
        .package(path: "Packages/KinemaPlayback"),
        .package(path: "Packages/KinemaUI"),
        .package(path: "Packages/KinemaSubtitles"),
        .package(path: "Packages/KinemaMedia"),
        .package(path: "Packages/KinemaPlugins"),
        .package(path: "Packages/KinemaPlaybill")
    ],
    targets: []
)
