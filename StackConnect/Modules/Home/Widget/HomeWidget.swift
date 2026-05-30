import SwiftUI

// MARK: - Kind

enum HomeWidgetKind: String, Codable, CaseIterable, Hashable, Identifiable {
    case inReview
    case awaitingRelease
    case recentReviews

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .inReview:
            return String(localized: "In Review")
        case .awaitingRelease:
            return String(localized: "Awaiting Release")
        case .recentReviews:
            return String(localized: "Recent Reviews")
        }
    }

    var summary: String {
        switch self {
        case .inReview:
            return String(localized: "Apps waiting on App Review")
        case .awaitingRelease:
            return String(localized: "Approved apps ready to release")
        case .recentReviews:
            return String(localized: "Latest customer reviews across your apps")
        }
    }

    var systemImage: String {
        switch self {
        case .inReview:
            return "magnifyingglass.circle.fill"
        case .awaitingRelease:
            return "paperplane.circle.fill"
        case .recentReviews:
            return "star.bubble.fill"
        }
    }

    var tintColor: Color {
        switch self {
        case .inReview:
            return .orange
        case .awaitingRelease:
            return .blue
        case .recentReviews:
            return .yellow
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
