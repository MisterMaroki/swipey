// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Swipey",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "Swipey",
            path: "Sources/Swipey"
        )
    ]
)
