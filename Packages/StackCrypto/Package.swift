// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "StackCrypto",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(
            name: "StackCrypto",
            targets: ["StackCrypto"]
        ),
    ],
    targets: [
        .target(
            name: "StackCrypto",
            path: "Sources/StackCrypto"
        ),
    ]
)
