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
    targets: [
        .target(
            name: "APIProviderFirebase",
            path: "Sources/APIProviderFirebase"
        ),
    ]
)
