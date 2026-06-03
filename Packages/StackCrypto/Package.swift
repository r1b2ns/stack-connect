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
    dependencies: [
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.0.0"),
    ],
    targets: [
        .target(
            name: "StackCrypto",
            dependencies: [
                .product(name: "Crypto", package: "swift-crypto"),
                .product(name: "_CryptoExtras", package: "swift-crypto"),
            ],
            path: "Sources/StackCrypto"
        ),
    ]
)
