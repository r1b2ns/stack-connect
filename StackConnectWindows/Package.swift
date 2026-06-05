// swift-tools-version: 5.9

import PackageDescription

// The Windows app executable (phase 4 · Block B).
//
// B1a (this step) is HEADLESS: no SwiftCrossUI yet. Its job is to prove the
// entire non-UI stack — SQLite storage, Windows Credential Manager secrets,
// crypto, the Firebase/Play providers, and the App Store Connect SDK — links
// into a single Windows executable, and that the per-platform bootstrap (B2)
// wires correctly. SwiftCrossUI and the first screen come in B1b.
//
//   swift run StackConnectWindows
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
    ]
)
