// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "APIProviderPlay",
    platforms: [.iOS(.v17)],
    products: [
        .library(
            name: "APIProviderPlay",
            targets: ["APIProviderPlay"]
        ),
    ],
    targets: [
        .target(
            name: "APIProviderPlay",
            path: "Sources/APIProviderPlay"
        ),
    ]
)
