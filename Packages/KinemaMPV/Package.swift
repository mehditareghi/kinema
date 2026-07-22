// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "KinemaMPV",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
        .tvOS(.v17)
    ],
    products: [
        .library(name: "KinemaMPV", targets: ["KinemaMPV"])
    ],
    dependencies: [
        .package(path: "../KinemaCore"),
        .package(path: "../MPVKitVendor")
    ],
    targets: [
        .target(
            name: "KinemaMPV",
            dependencies: [
                "KinemaCore",
                .product(name: "LibMPV", package: "MPVKitVendor")
            ],
            path: "Sources/KinemaMPV",
            cSettings: [
                .define("GLES_SILENCE_DEPRECATION", .when(platforms: [.iOS, .tvOS]))
            ],
            linkerSettings: [
                .linkedFramework("AVFoundation"),
                .linkedFramework("CoreMedia"),
                .linkedFramework("VideoToolbox"),
                .linkedFramework("OpenGLES", .when(platforms: [.iOS, .tvOS])),
                .linkedFramework("OpenGL", .when(platforms: [.macOS])),
                .linkedLibrary("c++")
            ]
        )
    ]
)
