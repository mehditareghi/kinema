// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "KinemaCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
        .tvOS(.v17)
    ],
    products: [
        .library(name: "KinemaCore", targets: ["KinemaCore"])
    ],
    targets: [
        .target(
            name: "KinemaCore",
            resources: [.process("Resources")]
        )
    ]
)
