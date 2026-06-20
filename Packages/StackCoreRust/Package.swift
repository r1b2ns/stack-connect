// swift-tools-version:5.9
import PackageDescription

// Vendored SwiftPM package wrapping the Rust core (stack_core) for the iOS app.
//
// The `StackCoreRust.xcframework` (iOS device + simulator slices) and the generated
// `Sources/StackCoreRust/StackCoreRust.swift` UniFFI wrapper are produced in the
// `stack-connect-core` repo by `./build/build-xcframework.sh` and copied here so the
// app does NOT depend on a sibling-repo relative path (robust, self-contained build).
//
// The module is named `StackCoreRust` to avoid colliding with the app's *native*
// `StackCore` Swift package (which is an unrelated storage/logging module).
let package = Package(
    name: "StackCoreRust",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "StackCoreRust", targets: ["StackCoreRust"]),
    ],
    targets: [
        .binaryTarget(
            name: "StackCoreFFI",
            path: "StackCoreRust.xcframework"
        ),
        .target(
            name: "StackCoreRust",
            dependencies: ["StackCoreFFI"],
            path: "Sources/StackCoreRust"
        ),
    ]
)
