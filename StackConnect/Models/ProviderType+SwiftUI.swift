#if canImport(SwiftUI)
import SwiftUI

/// iOS-only SwiftUI conveniences over the Foundation-pure `ProviderType`
/// (defined in `StackHomeCore`). These map the raw `iconSymbolName`/`colorName`
/// tokens onto SwiftUI types so the rest of the iOS app keeps using
/// `provider.iconName` / `provider.color` exactly as before.
extension ProviderType {

    /// SF Symbol name for use with `Image(systemName:)`.
    /// Alias of the pure `iconSymbolName` token, kept for call-site compatibility.
    var iconName: String {
        iconSymbolName
    }

    /// SwiftUI tint resolved from the pure `colorName` token.
    var color: Color {
        switch colorName {
        case "blue":   return .blue
        case "orange": return .orange
        case "green":  return .green
        default:       return .accentColor
        }
    }

    /// Convenience `Image` built from the provider's SF Symbol.
    var icon: Image {
        Image(systemName: iconSymbolName)
    }
}
#endif
