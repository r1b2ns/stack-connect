// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "APIProviderPlay",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(
            name: "APIProviderPlay",
            targets: ["APIProviderPlay"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.0.0"),
    ],
    targets: [
        .target(
            name: "APIProviderPlay",
            dependencies: [
                .product(name: "_CryptoExtras", package: "swift-crypto"),
            ],
            path: "Sources/APIProviderPlay"
        ),
    ]
)
