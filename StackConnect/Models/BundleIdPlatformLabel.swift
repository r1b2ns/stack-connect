import Foundation

/// Human, localized labels for App Store Connect `BundleIdPlatform` raw values
/// (`IOS`, `MAC_OS`, `UNIVERSAL`, `SERVICES`) as returned on bundle IDs,
/// devices, certificates and provisioning profiles.
///
/// Single source of truth so no screen shows the raw API enum.
enum BundleIdPlatformLabel {
    enum Style {
        /// "iOS" — for tags and detail rows of certificates / profiles.
        case short
        /// "iOS, tvOS, watchOS, visionOS" — spells out every OS an `IOS`
        /// bundle ID / device covers (Apple unified them under one value).
        case expanded
    }

    static func label(for raw: String, style: Style = .short) -> String {
        switch raw.uppercased() {
        case "IOS":
            return style == .expanded
                ? String(localized: "iOS, tvOS, watchOS, visionOS")
                : String(localized: "iOS")
        case "MAC_OS":    return String(localized: "macOS")
        case "UNIVERSAL": return String(localized: "Universal")
        case "SERVICES":  return String(localized: "Services")
        default:          return raw
        }
    }

    /// Optional-friendly variant: `nil` / empty shows an em dash.
    static func label(for raw: String?, style: Style = .short) -> String {
        guard let raw, !raw.isEmpty else { return "—" }
        return label(for: raw, style: style)
    }
}
