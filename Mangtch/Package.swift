// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "Mangtch",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
        .package(url: "https://github.com/sindresorhus/Defaults", from: "8.2.0"),
    ],
    targets: [
        .executableTarget(
            name: "Mangtch",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle"),
                .product(name: "Defaults", package: "Defaults"),
            ],
            path: "Sources",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("QuartzCore"),
                .linkedFramework("IOKit"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("AudioToolbox"),
            ]
        ),
        .testTarget(
            name: "MangtchTests",
            dependencies: ["Mangtch"],
            path: "Tests/MangtchTests"
        )
    ]
)
