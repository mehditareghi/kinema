// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "KinemaPlaybill",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
        .tvOS(.v17)
    ],
    products: [
        .library(name: "KinemaPlaybill", targets: ["KinemaPlaybill"])
    ],
    dependencies: [
        .package(path: "../KinemaCore"),
        .package(path: "../KinemaMedia")
    ],
    targets: [
        .target(
            name: "KinemaPlaybill",
            dependencies: ["KinemaCore", "KinemaMedia"]
        )
    ]
)
