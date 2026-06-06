#if canImport(SwiftUI)
import SwiftUI
import StackHomeCore

/// iOS-only SwiftUI conveniences over the Foundation-pure `HomeWidgetKind`
/// (defined in `StackHomeCore`). These map the raw `iconSymbolName`/`colorName`
/// tokens onto SwiftUI types so the rest of the iOS app keeps using
/// `kind.systemImage` / `kind.tintColor` exactly as before.
extension HomeWidgetKind {

    /// SF Symbol name for use with `Image(systemName:)`.
    /// Alias of the pure `iconSymbolName` token, kept for call-site compatibility.
    var systemImage: String {
        iconSymbolName
    }

    /// SwiftUI tint resolved from the pure `colorName` token.
    ///
    /// Reuses the same token→`Color` mapping convention established by T-A3 in
    /// `ProviderType+SwiftUI.swift` (blue/orange/green → system colors, default
    /// `.accentColor`), extended with the `yellow` token used by Recent Reviews.
    var tintColor: Color {
        switch colorName {
        case "blue":   return .blue
        case "orange": return .orange
        case "green":  return .green
        case "yellow": return .yellow
        default:       return .accentColor
        }
    }
}
#endif
