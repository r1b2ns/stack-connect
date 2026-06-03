// swift-tools-version: 5.9

import PackageDescription

// Headless proof-of-concept that exercises the shared, platform-agnostic logic
// on the host (and, crucially, on Windows). It links only the migrated packages —
// no SwiftUI, no UIKit — so a successful `swift run` on Windows is the phase-3 gate.
//
//   swift run StackConnectWindowsPoC      # core checks: SQLite + crypto + RSA
//   swift run WindowsSecretsProbe         # Windows Credential Manager round-trip
//
// The App Store Connect SDK gate lives in the sibling ../ASCBuildProbe package.
let package = Package(
    name: "StackConnectWindowsPoC",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(path: "../Packages/StackProtocols"),
        .package(path: "../Packages/StackCrypto"),
        .package(path: "../Packages/StackStorageSQLite"),
        .package(path: "../Packages/APIProviderFirebase"),
        .package(path: "../Packages/APIProviderPlay"),
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "StackConnectWindowsPoC",
            dependencies: [
                .product(name: "StackProtocols", package: "StackProtocols"),
                .product(name: "StackCrypto", package: "StackCrypto"),
                .product(name: "StackStorageSQLite", package: "StackStorageSQLite"),
                .product(name: "APIProviderFirebase", package: "APIProviderFirebase"),
                .product(name: "APIProviderPlay", package: "APIProviderPlay"),
                .product(name: "_CryptoExtras", package: "swift-crypto"),
            ],
            path: "Sources/StackConnectWindowsPoC"
        ),
        .executableTarget(
            name: "WindowsSecretsProbe",
            path: "Sources/WindowsSecretsProbe"
        ),
    ]
)
