import SwiftUI

// MARK: - Kind

enum HomeWidgetKind: String, Codable, CaseIterable, Hashable, Identifiable {
    case appStoreReviewCount

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .appStoreReviewCount:
            return String(localized: "App Store Activity")
        }
    }

    var summary: String {
        switch self {
        case .appStoreReviewCount:
            return String(localized: "Apps currently in review or rolling out")
        }
    }

    var systemImage: String {
        switch self {
        case .appStoreReviewCount:
            return "app.badge.fill"
        }
    }

    var tintColor: Color {
        switch self {
        case .appStoreReviewCount:
            return .blue
        }
    }
}

// MARK: - Size

enum HomeWidgetSize: String, Codable, Hashable {
    case compact
    case expanded
}

// MARK: - Configuration

struct HomeWidgetConfiguration: Identifiable, Codable, Hashable {
    let id: UUID
    let kind: HomeWidgetKind
    var size: HomeWidgetSize

    init(id: UUID = UUID(), kind: HomeWidgetKind, size: HomeWidgetSize = .expanded) {
        self.id = id
        self.kind = kind
        self.size = size
    }
}

// MARK: - Protocol

@MainActor
protocol HomeWidget: AnyObject {
    static var kind: HomeWidgetKind { get }
    var configuration: HomeWidgetConfiguration { get }
    var isLoading: Bool { get }
    func load() async
    func makeView() -> AnyView
}

extension HomeWidget {
    var id: UUID { configuration.id }
    var kind: HomeWidgetKind { Self.kind }
}
