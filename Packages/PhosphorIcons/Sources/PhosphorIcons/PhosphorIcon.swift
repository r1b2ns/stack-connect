import Foundation
import SwiftCrossUI
import ImageFormats

// MARK: - Icon Catalog

/// A curated set of Phosphor Icons bundled as 48×48 black-on-transparent PNGs.
///
/// Each case maps to a file in `Resources/`. Icons are loaded via
/// `Bundle.module` and can be tinted to any RGBA color at runtime using
/// `ImageFormats.Image<RGBA>.map()`.
///
/// Phosphor Icons: MIT © Phosphor Icons — https://phosphoricons.com
public enum PhosphorIcon: String, CaseIterable, Sendable {
    // Navigation
    case house = "house-bold"
    case arrowLeft = "arrow-left-bold"
    case caretRight = "caret-right-bold"
    case caretDown = "caret-down-bold"

    // Actions
    case magnifyingGlass = "magnifying-glass-bold"
    case arrowsClockwise = "arrows-clockwise-bold"
    case downloadSimple = "download-simple-bold"
    case uploadSimple = "upload-simple-bold"
    case archive = "archive-bold"

    // Objects
    case gearSix = "gear-six-bold"
    case star = "star-bold"
    case starFill = "star-fill"
    case globe = "globe-bold"
    case lockSimple = "lock-simple-bold"
    case info = "info-bold"
    case warning = "warning-bold"
    case barricade = "barricade-bold"
    case chatCircle = "chat-circle-bold"
    case fileText = "file-text-bold"
    case calendarBlank = "calendar-blank-bold"

    // Apps & Devices
    case storefront = "storefront-bold"
    case appWindow = "app-window-bold"
    case deviceMobile = "device-mobile-bold"
    case cube = "cube-bold"
    case bagSimple = "bag-simple-bold"
    case chartBar = "chart-bar-bold"
    case airplane = "airplane-bold"
    case play = "play-bold"
    case fire = "fire-bold"

    // People
    case user = "user-bold"
    case userCircle = "user-circle-bold"
    case wheelchair = "wheelchair-bold"
}

// MARK: - Loading & Tinting

extension PhosphorIcon {

    /// Loads the raw (black-on-transparent) PNG from the bundle.
    ///
    /// Returns `nil` if the resource is missing or unreadable.
    public func load() -> ImageFormats.Image<RGBA>? {
        guard let url = Bundle.module.url(
            forResource: rawValue,
            withExtension: "png",
            subdirectory: "Resources"
        ) else {
            return nil
        }

        guard let data = try? Data(contentsOf: url) else {
            return nil
        }

        return try? ImageFormats.Image<RGBA>.loadPNG(from: Array(data))
    }

    /// Loads the icon and tints every opaque pixel to the given RGBA color,
    /// preserving the original alpha channel for anti-aliased edges.
    ///
    /// - Parameters:
    ///   - r: Red component (0–255).
    ///   - g: Green component (0–255).
    ///   - b: Blue component (0–255).
    ///   - a: Alpha multiplier (0–255). Defaults to 255 (fully opaque).
    /// - Returns: A tinted `ImageFormats.Image<RGBA>`, or `nil` if loading fails.
    public func tinted(
        r: UInt8,
        g: UInt8,
        b: UInt8,
        a: UInt8 = 255
    ) -> ImageFormats.Image<RGBA>? {
        guard let source = load() else { return nil }
        return source.map { pixel in
            // Preserve the original alpha (anti-aliasing), multiply by the
            // requested alpha. The source is black-on-transparent so alpha
            // carries the shape; we replace the RGB channels entirely.
            let blendedAlpha = UInt8(
                (UInt16(pixel.alpha) * UInt16(a)) / 255
            )
            return RGBA(r, g, b, blendedAlpha)
        }
    }
}

// MARK: - SwiftCrossUI Image Convenience

extension PhosphorIcon {

    /// Returns a tinted `SwiftCrossUI.Image` ready for use in a view tree.
    ///
    /// ```swift
    /// PhosphorIcon.house.image(r: 150, g: 100, b: 255)
    ///     .resizable()
    ///     .frame(width: 20, height: 20)
    /// ```
    public func image(
        r: UInt8,
        g: UInt8,
        b: UInt8,
        a: UInt8 = 255
    ) -> SwiftCrossUI.Image? {
        guard let img = tinted(r: r, g: g, b: b, a: a) else { return nil }
        return SwiftCrossUI.Image(img)
    }
}
