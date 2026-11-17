import SwiftUI

enum ProviderType: String, Codable, CaseIterable, Hashable {
    case apple
    case firebase
    case googlePlay

    var displayName: String {
        switch self {
        case .apple:      return String(localized: "App Store Connect")
        case .firebase:   return String(localized: "Firebase")
        case .googlePlay: return String(localized: "Google Play")
        }
    }

    var iconName: String {
        switch self {
        case .apple:      return "apple.logo"
        case .firebase:   return "flame.fill"
        case .googlePlay: return "play.fill"
        }
    }

    var color: Color {
        switch self {
        case .apple:      return .blue
        case .firebase:   return .orange
        case .googlePlay: return .green
        }
    }

    // MARK: - Capabilities

    /// Whether accounts of this provider can be exported to an encrypted
    /// `.scexport` file. Drives every export entry point (see
    /// `AccountModel.isExportable`) and `AccountExporter`.
    var supportsExport: Bool {
        switch self {
        case .apple, .googlePlay: return true
        case .firebase:           return false
        }
    }

    /// Whether the provider's account list offers importing a `.scexport` file.
    /// Settings › Accounts keeps accepting any provider's file, so `.scexport`
    /// files already in circulation stay importable.
    var supportsImport: Bool {
        switch self {
        case .apple, .googlePlay: return true
        case .firebase:           return false
        }
    }

    /// Whether accounts carry an `AccountRole` (picker in Add Account and
    /// Account Settings, badge in the account lists). The role is an App Store
    /// Connect concept, so Google Play accounts always keep `.unspecified`.
    /// Firebase keeps the picker it always had.
    var supportsAccountRole: Bool {
        switch self {
        case .apple, .firebase: return true
        case .googlePlay:       return false
        }
    }
}
