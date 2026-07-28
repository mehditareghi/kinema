// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "KinemaSharing",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
        .tvOS(.v17)
    ],
    products: [
        .library(name: "KinemaSharing", targets: ["KinemaSharing"])
    ],
    dependencies: [
        .package(path: "../KinemaCore"),
        .package(path: "../KinemaMedia"),
        .package(path: "../../Vendor/GCDWebServer")
    ],
    targets: [
        .target(
            name: "KinemaSharing",
            dependencies: [
                "KinemaCore",
                "KinemaMedia",
                .product(name: "GCDWebServer", package: "GCDWebServer")
            ],
            resources: [
                .process("Resources")
            ]
        )
    ]
)
