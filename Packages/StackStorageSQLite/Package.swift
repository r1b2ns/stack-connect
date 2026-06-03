// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "StackStorageSQLite",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(
            name: "StackStorageSQLite",
            targets: ["StackStorageSQLite"]
        ),
    ],
    dependencies: [
        .package(path: "../StackProtocols"),
    ],
    targets: [
        // Vendored SQLite amalgamation (see Sources/CSQLite/SQLITE_VERSION.txt).
        // Bundled rather than linking the system library so the same source
        // builds on Windows, where SQLite is not a system dependency.
        .target(
            name: "CSQLite",
            path: "Sources/CSQLite"
        ),
        .target(
            name: "StackStorageSQLite",
            dependencies: [
                "CSQLite",
                .product(name: "StackProtocols", package: "StackProtocols"),
            ],
            path: "Sources/StackStorageSQLite"
        ),
        .testTarget(
            name: "StackStorageSQLiteTests",
            dependencies: ["StackStorageSQLite"],
            path: "Tests/StackStorageSQLiteTests"
        ),
    ]
)
