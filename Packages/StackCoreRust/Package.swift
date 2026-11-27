// swift-tools-version:5.9
import PackageDescription

// SwiftPM package wrapping the Rust core (stack_core) for the iOS app.
//
// The `StackCoreFFI` binary (iOS device + simulator slices) is a prebuilt xcframework
// downloaded by SwiftPM from the `stack-connect-core` GitHub release, so a fresh clone
// builds with no Rust toolchain. The generated UniFFI wrapper
// `Sources/StackCoreRust/StackCoreRust.swift` is vendored here.
//
// Updating to a new core version (wrapper and binary MUST come from the same core commit):
//   1. In `stack-connect-core`, run `./build/build-xcframework.sh`.
//   2. Copy the generated `StackCoreRust.swift` wrapper into `Sources/StackCoreRust/`.
//   3. Rename the xcframework to `StackCoreFFI.xcframework` (must match the binary target
//      name) and zip it: `ditto -c -k --keepParent StackCoreFFI.xcframework StackCoreFFI.xcframework.zip`.
//   4. Attach the zip to a new `stack-connect-core` release.
//   5. Update `url` below and set `checksum` to `swift package compute-checksum StackCoreFFI.xcframework.zip`.
//
// For local iteration on the core, temporarily switch the binary target back to
// `path: "StackCoreRust.xcframework"` pointing at a local build; the `.gitignore` entry
// keeps that local copy out of git. Do not commit the `path:` variant.
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
            url: "https://github.com/r1b2ns/stack-connect-core/releases/download/1.1.0/StackCoreFFI.xcframework.zip",
            checksum: "a0513d2e160201eb06848f1251fe8b602b7f5ec7b34f32b50eff7fe4df6d7c66"
        ),
        .target(
            name: "StackCoreRust",
            dependencies: ["StackCoreFFI"],
            path: "Sources/StackCoreRust"
        ),
    ]
)
