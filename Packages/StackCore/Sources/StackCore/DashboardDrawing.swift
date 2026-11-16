import SwiftUI

// Drawing vocabulary of the Home dashboard rows (in-app widgets and the WidgetKit
// extension), provider-neutral so App Store and Google Play rows render with the
// same views (plan section 6, H1/H6). Shared by the app and the extension.

/// The platform a dashboard row belongs to: an App Store platform or Android.
public enum DashboardPlatform: String, Codable, Hashable, Sendable, CaseIterable {
    case iOS = "IOS"
    case macOS = "MAC_OS"
    case tvOS = "TV_OS"
    case visionOS = "VISION_OS"
    case android = "ANDROID"

    /// Tolerates the alias spellings the App Store Connect API returns
    /// (`TVOS`, `MACOS`, `XROS`).
    public init?(raw: String?) {
        switch raw?.uppercased() {
        case "IOS":                 self = .iOS
        case "MAC_OS", "MACOS":     self = .macOS
        case "TV_OS", "TVOS":       self = .tvOS
        case "VISION_OS", "XROS":   self = .visionOS
        case "ANDROID":             self = .android
        default:                    return nil
        }
    }

    /// Platform names are proper nouns and stay untranslated.
    public var displayName: String {
        switch self {
        case .iOS:      return "iOS"
        case .macOS:    return "macOS"
        case .tvOS:     return "tvOS"
        case .visionOS: return "visionOS"
        case .android:  return "Android"
        }
    }

    /// SF Symbol of the platform glyph, `nil` for Android (SF Symbols has no
    /// Android glyph: each target draws its `AndroidGlyph` asset instead).
    public var systemImage: String? {
        switch self {
        case .iOS:      return "apple.logo"
        case .macOS:    return "macbook"
        case .tvOS:     return "appletv"
        case .visionOS: return "visionpro"
        case .android:  return nil
        }
    }

    /// Group order on the dashboard: Apple platforms, then Android.
    public var sortRank: Int {
        switch self {
        case .iOS:      return 0
        case .macOS:    return 1
        case .tvOS:     return 2
        case .visionOS: return 3
        case .android:  return 4
        }
    }
}

/// Status dot color of a dashboard row.
public enum DashboardStatusColor: String, Codable, Hashable, Sendable {
    case green, orange, red, gray, blue, yellow

    public var color: Color {
        switch self {
        case .green:  return .green
        case .orange: return .orange
        case .red:    return .red
        case .gray:   return .gray
        case .blue:   return .blue
        case .yellow: return .yellow
        }
    }
}

/// Progress drawn under an Awaiting Release row.
public enum DashboardProgress: Codable, Hashable, Sendable {
    /// App Store phased release: day `day` of `total`.
    case phased(day: Int, total: Int, paused: Bool)
    /// Google Play staged rollout: `fraction` in (0, 1), read from the tracks
    /// cache at `asOf` (plan H3: background sync can't read it without an edit).
    case rollout(fraction: Double, halted: Bool, asOf: Date?)

    /// Bar value in 0…1.
    public var value: Double {
        switch self {
        case let .phased(day, total, _):
            guard total > 0 else { return 0 }
            return Double(min(max(day, 0), total)) / Double(total)
        case let .rollout(fraction, _, _):
            return min(max(fraction, 0), 1)
        }
    }

    /// Bar color (prototype `.prog`): teal for an App Store phased release,
    /// blue for a Play staged rollout, orange when paused or halted.
    public var barColor: Color {
        if isPaused { return .orange }
        switch self {
        case .phased:  return .teal
        case .rollout: return .blue
        }
    }

    /// Paused phased release or halted rollout.
    public var isPaused: Bool {
        switch self {
        case let .phased(_, _, paused):   return paused
        case let .rollout(_, halted, _):  return halted
        }
    }
}
