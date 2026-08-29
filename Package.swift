// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "EdgeStash",
    platforms: [
        .macOS(.v12)
    ],
    products: [
        .library(name: "EdgeStashLogic", targets: ["EdgeStashLogic"]),
        .executable(name: "EdgeStashLogicTests", targets: ["EdgeStashLogicTests"])
    ],
    targets: [
        .target(
            name: "EdgeStashLogic",
            path: "Sources/EdgeStashLogic"
        ),
        .executableTarget(
            name: "EdgeStashLogicTests",
            dependencies: ["EdgeStashLogic"],
            path: "Tests"
        )
    ]
)
