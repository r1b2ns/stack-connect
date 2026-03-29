// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "StackProtocols",
    platforms: [.iOS(.v17)],
    products: [
        .library(
            name: "StackProtocols",
            targets: ["StackProtocols"]
        ),
    ],
    targets: [
        .target(
            name: "StackProtocols",
            path: "Sources/StackProtocols"
        ),
    ]
)
