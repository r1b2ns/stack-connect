// swift-tools-version: 5.10

import PackageDescription

// The Windows app GUI (phase 4 · B1b) — SwiftCrossUI.
//
// Kept in its OWN package, separate from ../StackConnectWindows (the headless
// core). SwiftCrossUI's DefaultBackend resolves every backend's dependencies
// (incl. AndroidKit / swift-java), a large graph that must not be dragged into
// the headless package's resolution. Starts as the smallest possible window to
// validate the WinUI backend on the VM; real screens land on top in later steps,
// at which point this package also picks up the local non-UI packages.
//
//   swift run StackConnectWindowsApp
//
// NOTE (Windows): SwiftCrossUI's transitive deps (swift-argument-parser,
// swift-java, jpeg) contain symlinks. git on Windows can't check those out
// unless symlinks are allowed — set `git config --global core.symlinks false`
// (writes them as plain files; they live only in plugin/sample/test dirs) or
// enable Windows Developer Mode. v0.7.x requires tools 5.10.
let package = Package(
    name: "StackConnectWindowsApp",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/moreSwift/swift-cross-ui", .upToNextMinor(from: "0.7.0")),
        // Shared Home logic core. Foundation-pure (depends only on
        // StackProtocols), so it does NOT drag a heavy graph into resolution —
        // safe to add per the note above. StackHomeCore's manifest references
        // ../StackProtocols, which resolves under Packages/ alongside it.
        .package(path: "../Packages/StackHomeCore"),
        // Storage protocols + the cross-platform persistence/secret backends the
        // B2 bootstrap wires into the core HomeViewModel. All Foundation-pure
        // (StackProtocols) or light C-target/Win32 packages already used by the
        // headless StackConnectWindows exe — no heavy graph.
        .package(path: "../Packages/StackProtocols"),
        .package(path: "../Packages/StackStorageSQLite"),
        .package(path: "../Packages/StackSecretsWindows"),
        .package(path: "../Packages/StackCrypto"),
        // Phosphor Icons — curated PNG icons with runtime tinting for SwiftCrossUI.
        // The original phosphor-icons/swift SPM depends on Apple's SwiftUI, so this
        // local package bundles PNGs and tints via ImageFormats.Image<RGBA>.
        .package(path: "../Packages/PhosphorIcons"),
        // App Store Connect SDK (windows-support branch). Added to the
        // executable target only — WindowsAppCore stays SDK-free so it
        // remains fully testable without the SDK's transitive graph.
        .package(url: "https://github.com/r1b2ns/appstoreconnect-swift-sdk.git", branch: "windows-support"),
    ],
    targets: [
        // Library target containing testable business logic (models, view models).
        // Separated from the executable so unit tests can `@testable import` it
        // without linking the `@main` entry point.
        .target(
            name: "WindowsAppCore",
            dependencies: [
                .product(name: "SwiftCrossUI", package: "swift-cross-ui"),
                .product(name: "StackHomeCore", package: "StackHomeCore"),
                .product(name: "StackProtocols", package: "StackProtocols"),
                .product(name: "StackCrypto", package: "StackCrypto"),
            ],
            path: "Sources/WindowsAppCore"
        ),
        .executableTarget(
            name: "StackConnectWindowsApp",
            dependencies: [
                "WindowsAppCore",
                .product(name: "SwiftCrossUI", package: "swift-cross-ui"),
                .product(name: "DefaultBackend", package: "swift-cross-ui"),
                .product(name: "StackHomeCore", package: "StackHomeCore"),
                .product(name: "StackProtocols", package: "StackProtocols"),
                .product(name: "StackStorageSQLite", package: "StackStorageSQLite"),
                .product(name: "StackSecretsWindows", package: "StackSecretsWindows"),
                .product(name: "StackCrypto", package: "StackCrypto"),
                .product(name: "AppStoreConnect-Swift-SDK", package: "appstoreconnect-swift-sdk"),
                .product(name: "PhosphorIcons", package: "PhosphorIcons"),
            ],
            path: "Sources/StackConnectWindowsApp"
        ),
        .testTarget(
            name: "WindowsAppCoreTests",
            dependencies: [
                "WindowsAppCore",
                .product(name: "StackHomeCore", package: "StackHomeCore"),
                .product(name: "StackProtocols", package: "StackProtocols"),
                .product(name: "StackCrypto", package: "StackCrypto"),
            ],
            path: "Tests/WindowsAppCoreTests"
        ),
    ]
)
