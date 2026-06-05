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
    ],
    targets: [
        // `KeyStorable` backed by the Windows Credential Manager. The Win32 body
        // is gated `#if os(Windows)`; on other platforms an in-memory fallback
        // keeps the type building/testable on the macOS host. This package is
        // never part of the iOS app target (kept out of project.yml).
        .target(
            name: "StackSecretsWindows",
            dependencies: [
                .product(name: "StackProtocols", package: "StackProtocols"),
            ],
            path: "Sources/StackSecretsWindows"
        ),
        .testTarget(
            name: "StackSecretsWindowsTests",
            dependencies: ["StackSecretsWindows"],
            path: "Tests/StackSecretsWindowsTests"
        ),
    ]
)
