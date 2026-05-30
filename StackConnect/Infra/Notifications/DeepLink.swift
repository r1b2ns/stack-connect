import Foundation

/// In-app deep links used by widgets and local notifications. Scheme: `stackconnect`.
///
/// - `home`    → `stackconnect://home`
/// - `reviews` → `stackconnect://reviews`
/// - `app`     → `stackconnect://app/{accountId}/{appId}`
/// - `review`  → `stackconnect://review/{accountId}/{appId}/{reviewId}`
enum DeepLink: Equatable {
    case home
    case reviews
    case app(accountId: String, appId: String)
    case review(accountId: String, appId: String, reviewId: String)

    static let scheme = "stackconnect"

    var url: URL {
        var components = URLComponents()
        components.scheme = Self.scheme
        switch self {
        case .home:
            components.host = "home"
        case .reviews:
            components.host = "reviews"
        case let .app(accountId, appId):
            components.host = "app"
            components.path = "/" + [accountId, appId].map(Self.encode).joined(separator: "/")
        case let .review(accountId, appId, reviewId):
            components.host = "review"
            components.path = "/" + [accountId, appId, reviewId].map(Self.encode).joined(separator: "/")
        }
        // Fallback should never trigger; host strings above are always valid.
        return components.url ?? URL(string: "\(Self.scheme)://home")!
    }

    init?(url: URL) {
        guard url.scheme == Self.scheme else { return nil }
        // pathComponents drops the leading "/" element after the host.
        let segments = url.pathComponents.filter { $0 != "/" }.map { $0.removingPercentEncoding ?? $0 }
        switch url.host {
        case "home":
            self = .home
        case "reviews":
            self = .reviews
        case "app" where segments.count >= 2:
            self = .app(accountId: segments[0], appId: segments[1])
        case "review" where segments.count >= 3:
            self = .review(accountId: segments[0], appId: segments[1], reviewId: segments[2])
        default:
            return nil
        }
    }

    private static func encode(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? value
    }
}
