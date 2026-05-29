// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "StackCore",
    platforms: [.iOS(.v17)],
    products: [
        .library(
            name: "StackCore",
            targets: ["StackCore"]
        ),
    ],
    targets: [
        .target(
            name: "StackCore",
            path: "Sources/StackCore"
        ),
    ]
)
