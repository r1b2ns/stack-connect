import SwiftUI

enum ProviderType: String, Codable, CaseIterable, Hashable {
    case apple
    case firebase

    var displayName: String {
        switch self {
        case .apple:    return String(localized: "App Store Connect")
        case .firebase: return String(localized: "Firebase")
        }
    }

    var iconName: String {
        switch self {
        case .apple:    return "apple.logo"
        case .firebase: return "flame.fill"
        }
    }

    var color: Color {
        switch self {
        case .apple:    return .blue
        case .firebase: return .orange
        }
    }
}
