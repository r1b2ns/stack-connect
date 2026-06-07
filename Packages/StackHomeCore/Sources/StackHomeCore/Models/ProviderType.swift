import Foundation

/// Identifies which backend a stored account belongs to.
///
/// This is the **Foundation-pure** definition consumed by both the iOS app and
/// the Windows port. It deliberately exposes only *raw string tokens*
/// (`iconSymbolName`, `colorName`) instead of SwiftUI types so it can compile on
/// non-Apple platforms with no `SwiftUI`/`UIKit`/`AppKit` dependency.
///
/// The iOS app re-adds SwiftUI conveniences (`Color`, `Image(systemName:)`) over
/// these tokens in `ProviderType+SwiftUI.swift` (iOS-only). The Windows port maps
/// the same tokens to its own glyphs/colors.
public enum ProviderType: String, Codable, CaseIterable, Hashable, Sendable, Identifiable {
    case apple
    case firebase
    case googlePlay

    /// Stable identity (the raw value), e.g. for SwiftUI `sheet(item:)` / `ForEach`.
    public var id: String { rawValue }

    /// Localized, user-facing name of the provider.
    public var displayName: String {
        switch self {
        case .apple:      return localizedString("App Store Connect")
        case .firebase:   return localizedString("Firebase")
        case .googlePlay: return localizedString("Google Play")
        }
    }

    /// Raw SF Symbol name token. iOS renders this via `Image(systemName:)`;
    /// other platforms map it to their own iconography.
    public var iconSymbolName: String {
        switch self {
        case .apple:      return "apple.logo"
        case .firebase:   return "flame.fill"
        case .googlePlay: return "play.fill"
        }
    }

    /// Raw color token (a system-color name). iOS resolves this to a SwiftUI
    /// `Color`; other platforms map it to their own palette.
    public var colorName: String {
        switch self {
        case .apple:      return "blue"
        case .firebase:   return "orange"
        case .googlePlay: return "green"
        }
    }
}
