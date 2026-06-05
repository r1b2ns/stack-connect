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
    ],
    targets: [
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
