// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "StackSecretsWindows",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(
            name: "StackSecretsWindows",
            targets: ["StackSecretsWindows"]
        ),
    ],
    dependencies: [
        .package(path: "../StackProtocols"),
        // Test-only: the prefs-store round-trip test persists
        // `[HomeWidgetConfiguration]` (defined in StackHomeCore) to prove the
        // same widget config the iOS app stores survives this Windows store.
        // The library target itself depends ONLY on StackProtocols.
        .package(path: "../StackHomeCore"),
    ],
    targets: [
        // `WindowsCredentialStorable` (secrets, Credential Manager) and
        // `WindowsFilePreferencesStorable` (non-secret prefs, JSON file under
        // %APPDATA%\StackConnect). The platform bodies are gated `#if os(Windows)`;
        // on other platforms a host fallback keeps both types building/testable
        // on the macOS host. This package is never part of the iOS app target
        // (kept out of project.yml).
        .target(
            name: "StackSecretsWindows",
            dependencies: [
                .product(name: "StackProtocols", package: "StackProtocols"),
            ],
            path: "Sources/StackSecretsWindows"
        ),
        .testTarget(
            name: "StackSecretsWindowsTests",
            dependencies: [
                "StackSecretsWindows",
                .product(name: "StackHomeCore", package: "StackHomeCore"),
            ],
            path: "Tests/StackSecretsWindowsTests"
        ),
    ]
)
