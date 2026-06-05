// swift-tools-version: 5.9

import PackageDescription

// Isolated probe for the phase-3 gate: does `appstoreconnect-swift-sdk` compile
// on Windows? Kept in its own package so a build failure here says nothing about
// the rest of the port.
//
//   swift build       # success == the SDK compiles for the host/Windows toolchain
//   swift run         # also link-checks and runs a trivial symbol reference
let package = Package(
    name: "ASCBuildProbe",
    platforms: [.macOS(.v13)],
    dependencies: [
        // windows-support: adds OpenCombine on Windows so the SDK doesn't fall back
        // to Apple's Combine. Probe branch only — the iOS app still tracks master.
        .package(url: "https://github.com/r1b2ns/appstoreconnect-swift-sdk.git", branch: "windows-support"),
    ],
    targets: [
        .executableTarget(
            name: "ASCBuildProbe",
            dependencies: [
                .product(name: "AppStoreConnect-Swift-SDK", package: "appstoreconnect-swift-sdk"),
            ],
            path: "Sources/ASCBuildProbe"
        ),
    ]
)
