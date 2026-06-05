// swift-tools-version: 5.9

import PackageDescription

// The Windows app — HEADLESS core (phase 4 · B1a).
//
// Proves the entire non-UI stack — SQLite storage, Windows Credential Manager
// secrets, crypto, the Firebase/Play providers, and the App Store Connect SDK —
// links into a single Windows executable, and that the per-platform bootstrap
// (B2) wires correctly.
//
//   swift run StackConnectWindows
//
// The SwiftCrossUI GUI lives in a SEPARATE package (../StackConnectWindowsApp)
// on purpose: SwiftCrossUI drags in a large transitive graph (swift-java,
// AndroidKit, …) that must not poison this package's resolution. Kept out of
// project.yml — the iOS app is unaffected.
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
