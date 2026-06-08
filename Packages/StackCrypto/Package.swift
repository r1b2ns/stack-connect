// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "StackCrypto",
    // macOS/iOS minimum needed for CryptoKit availability on Apple platforms.
    // SPM ignores the `platforms` array entirely on non-Darwin (Windows, Linux),
    // so this does NOT restrict cross-platform builds.
    platforms: [.macOS(.v13), .iOS(.v15)],
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
