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
}
