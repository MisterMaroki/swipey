// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Swipey",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.8.1")
    ],
    targets: [
        .target(
            name: "SwipeyLib",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Sources/Swipey",
            exclude: ["main.swift", "Info.plist"],
            swiftSettings: [
                .define("SWIPEY_LIB")
            ]
        ),
        .executableTarget(
            name: "Swipey",
            dependencies: ["SwipeyLib"],
            path: "Sources/SwipeyApp",
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@loader_path/../Frameworks"])
            ]
        ),
        .testTarget(
            name: "SwipeyTests",
            dependencies: ["SwipeyLib"],
            path: "Tests/SwipeyTests"
        )
    ]
)
