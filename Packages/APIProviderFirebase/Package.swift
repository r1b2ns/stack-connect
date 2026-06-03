// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "APIProviderFirebase",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(
            name: "APIProviderFirebase",
            targets: ["APIProviderFirebase"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.0.0"),
    ],
    targets: [
        .target(
            name: "APIProviderFirebase",
            dependencies: [
                .product(name: "_CryptoExtras", package: "swift-crypto"),
            ],
            path: "Sources/APIProviderFirebase"
        ),
    ]
)
