// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Swipey",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .target(
            name: "SwipeyLib",
            path: "Sources/Swipey",
            exclude: ["main.swift", "Info.plist"],
            swiftSettings: [
                .define("SWIPEY_LIB")
            ]
        ),
        .executableTarget(
            name: "Swipey",
            dependencies: ["SwipeyLib"],
            path: "Sources/SwipeyApp"
        ),
        .testTarget(
            name: "SwipeyTests",
            dependencies: ["SwipeyLib"],
            path: "Tests/SwipeyTests"
        )
    ]
)
