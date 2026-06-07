// swift-tools-version: 5.9

import PackageDescription

// StackHomeCore — the Foundation-pure shared Home logic core consumed by both
// the iOS Xcode project and the Windows app (StackConnectWindowsApp).
//
// It depends ONLY on StackProtocols and imports nothing platform-specific:
// no UIKit / SwiftUI / WidgetKit / UserNotifications / AppKit. Combine, when
// later required, is gated behind `#if canImport(Combine)`. This keeps the
// package buildable on the Windows toolchain (no Apple-only platform gates in
// the manifest). The Home models, widget data types, SyncService pipeline and
// the platform-agnostic HomeViewModel land here in T-A3…T-A10.
let package = Package(
    name: "StackHomeCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(
            name: "StackHomeCore",
            targets: ["StackHomeCore"]
        ),
    ],
    dependencies: [
        .package(path: "../StackProtocols"),
    ],
    targets: [
        .target(
            name: "StackHomeCore",
            dependencies: [
                .product(name: "StackProtocols", package: "StackProtocols"),
            ],
            path: "Sources/StackHomeCore"
        ),
        .testTarget(
            name: "StackHomeCoreTests",
            dependencies: ["StackHomeCore"],
            path: "Tests/StackHomeCoreTests"
        ),
    ]
)
