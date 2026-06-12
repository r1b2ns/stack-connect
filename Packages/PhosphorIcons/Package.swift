// swift-tools-version: 5.10

import PackageDescription

// PhosphorIcons — lightweight local package providing Phosphor Icons as
// tintable PNG resources for SwiftCrossUI apps.
//
// The original phosphor-icons/swift SPM package depends on Apple's SwiftUI
// (returns `SwiftUI.Image`), which is incompatible with SwiftCrossUI. This
// package bundles a curated set of 48×48 black-on-transparent PNGs from the
// Phosphor Icons project (MIT license) and exposes a `PhosphorIcon` enum
// that loads and tints them at runtime via `ImageFormats.Image<RGBA>`.
//
// Usage:
//   import PhosphorIcons
//   let tinted = PhosphorIcon.house.tinted(r: 100, g: 100, b: 255) // returns ImageFormats.Image<RGBA>?
//   if let img = tinted { Image(img).resizable().frame(width: 20, height: 20) }
//
// To add more icons: drop a new 48×48 PNG into Resources/, add a case to
// `PhosphorIcon`, and map it in `filename`.
let package = Package(
    name: "PhosphorIcons",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "PhosphorIcons", targets: ["PhosphorIcons"]),
    ],
    dependencies: [
        .package(url: "https://github.com/moreSwift/swift-cross-ui", .upToNextMinor(from: "0.7.0")),
    ],
    targets: [
        .target(
            name: "PhosphorIcons",
            dependencies: [
                .product(name: "SwiftCrossUI", package: "swift-cross-ui"),
            ],
            path: "Sources/PhosphorIcons",
            resources: [
                .copy("Resources"),
            ]
        ),
    ]
)
