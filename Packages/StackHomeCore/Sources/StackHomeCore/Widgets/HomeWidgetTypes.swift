import Foundation

// MARK: - Kind

/// Identifies a kind of Home dashboard widget.
///
/// This is the **Foundation-pure** definition consumed by both the iOS app and
/// the Windows port. Following the same split pattern as `ProviderType`, it
/// exposes only *raw string tokens* (`iconSymbolName`, `colorName`) instead of
/// SwiftUI types, so it compiles on non-Apple platforms with no
/// `SwiftUI`/`UIKit`/`AppKit` dependency.
///
/// The iOS app re-adds SwiftUI conveniences (`systemImage`, `tintColor`) over
/// these tokens in `HomeWidgetKind+SwiftUI.swift` (iOS-only). The Windows port
/// maps the same tokens to its own glyphs/colors.
public enum HomeWidgetKind: String, Codable, CaseIterable, Hashable, Identifiable, Sendable {
    case inReview
    case awaitingRelease
    case recentReviews

    /// Stable identity (the raw value).
    public var id: String { rawValue }

    /// Localized, user-facing name of the widget.
    public var displayName: String {
        switch self {
        case .inReview:
            return localizedString("In Review")
        case .awaitingRelease:
            return localizedString("Awaiting Release")
        case .recentReviews:
            return localizedString("Recent Reviews")
        }
    }

    /// Localized one-line description shown in the Customize Widgets panel.
    public var summary: String {
        switch self {
        case .inReview:
            return localizedString("Apps waiting on App Review")
        case .awaitingRelease:
            return localizedString("Approved apps ready to release")
        case .recentReviews:
            return localizedString("Latest customer reviews across your apps")
        }
    }

    /// Raw SF Symbol name token. iOS renders this via `Image(systemName:)`;
    /// other platforms map it to their own iconography.
    public var iconSymbolName: String {
        switch self {
        case .inReview:
            return "magnifyingglass.circle.fill"
        case .awaitingRelease:
            return "paperplane.circle.fill"
        case .recentReviews:
            return "star.bubble.fill"
        }
    }

    /// Raw color token (a system-color name). iOS resolves this to a SwiftUI
    /// `Color`; other platforms map it to their own palette.
    public var colorName: String {
        switch self {
        case .inReview:
            return "orange"
        case .awaitingRelease:
            return "blue"
        case .recentReviews:
            return "yellow"
        }
    }
}

// MARK: - Size

public enum HomeWidgetSize: String, Codable, Hashable, Sendable {
    case compact
    case expanded
}

// MARK: - Configuration

/// Persisted, Foundation-pure description of a single widget instance on the
/// Home dashboard. Serialized via `KeyStorable` under `home.widget.configurations`.
public struct HomeWidgetConfiguration: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public let kind: HomeWidgetKind
    public var size: HomeWidgetSize

    public init(id: UUID = UUID(), kind: HomeWidgetKind, size: HomeWidgetSize = .expanded) {
        self.id = id
        self.kind = kind
        self.size = size
    }
}
