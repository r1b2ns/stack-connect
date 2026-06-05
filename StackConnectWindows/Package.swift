// swift-tools-version: 5.10

import PackageDescription

// The Windows app executable (phase 4 · Block B).
//
// Two executables:
//   • StackConnectWindows    — HEADLESS (B1a). Proves the whole non-UI stack
//     (SQLite, Credential Manager, crypto, Firebase/Play, App Store Connect SDK)
//     links into one executable and the per-platform bootstrap (B2) wires up.
//       swift run StackConnectWindows
//   • StackConnectWindowsApp — SwiftCrossUI GUI (B1b). Starts as the smallest
//     possible window to validate the WinUI backend on the VM; real screens land
//     incrementally on top. Renders via WinUI on Windows, AppKit on macOS.
//       swift run StackConnectWindowsApp
//
// Depends on the SDK fork's `windows-support` branch (Combine made optional so
// it compiles on Windows). Kept out of project.yml — the iOS app is unaffected.
let package = Package(
    name: "StackConnectWindows",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(path: "../Packages/StackProtocols"),
        .package(path: "../Packages/StackCrypto"),
        .package(path: "../Packages/StackStorageSQLite"),
        .package(path: "../Packages/StackSecretsWindows"),
        .package(path: "../Packages/APIProviderFirebase"),
        .package(path: "../Packages/APIProviderPlay"),
        .package(url: "https://github.com/r1b2ns/appstoreconnect-swift-sdk.git", branch: "windows-support"),
        // SwiftCrossUI: cross-platform declarative UI. DefaultBackend selects
        // WinUI on Windows / AppKit on macOS. v0.7.x requires tools 5.10.
        .package(url: "https://github.com/moreSwift/swift-cross-ui", .upToNextMinor(from: "0.7.0")),
    ],
    targets: [
        .executableTarget(
            name: "StackConnectWindows",
            dependencies: [
                .product(name: "StackProtocols", package: "StackProtocols"),
                .product(name: "StackCrypto", package: "StackCrypto"),
                .product(name: "StackStorageSQLite", package: "StackStorageSQLite"),
                .product(name: "StackSecretsWindows", package: "StackSecretsWindows"),
                .product(name: "APIProviderFirebase", package: "APIProviderFirebase"),
                .product(name: "APIProviderPlay", package: "APIProviderPlay"),
                .product(name: "AppStoreConnect-Swift-SDK", package: "appstoreconnect-swift-sdk"),
            ],
            path: "Sources/StackConnectWindows"
        ),
        .executableTarget(
            name: "StackConnectWindowsApp",
            dependencies: [
                .product(name: "SwiftCrossUI", package: "swift-cross-ui"),
                .product(name: "DefaultBackend", package: "swift-cross-ui"),
            ],
            path: "Sources/StackConnectWindowsApp"
        ),
    ]
)
