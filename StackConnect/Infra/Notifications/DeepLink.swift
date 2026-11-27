import Foundation

/// In-app deep links used by widgets, local notifications and App Store
/// In-App Events. Scheme: `stackconnect`.
///
/// - `home`         → `stackconnect://home`
/// - `reviews`      → `stackconnect://reviews`
/// - `networkAudit` → `stackconnect://network-audit` (Settings › Privacy ›
///   Audit; the App Store In-App Event link. Falls back to Home while the
///   `networkAudit` flag is OFF)
/// - `app`          → `stackconnect://app/{accountId}/{appId}`
/// - `review`       → `stackconnect://review/{accountId}/{appId}/{reviewId}`
/// - `reimport`     → `stackconnect://reimport/{accountId}`
enum DeepLink: Equatable {
    case home
    case reviews
    case networkAudit
    case app(accountId: String, appId: String)
    case review(accountId: String, appId: String, reviewId: String)
    case reimport(accountId: String)

    static let scheme = "stackconnect"

    var url: URL {
        var components = URLComponents()
        components.scheme = Self.scheme
        switch self {
        case .home:
            components.host = "home"
        case .reviews:
            components.host = "reviews"
        case .networkAudit:
            components.host = "network-audit"
        case let .app(accountId, appId):
            components.host = "app"
            components.path = "/" + [accountId, appId].map(Self.encode).joined(separator: "/")
        case let .review(accountId, appId, reviewId):
            components.host = "review"
            components.path = "/" + [accountId, appId, reviewId].map(Self.encode).joined(separator: "/")
        case let .reimport(accountId):
            components.host = "reimport"
            components.path = "/" + Self.encode(accountId)
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
        case "network-audit":
            self = .networkAudit
        case "app" where segments.count >= 2:
            self = .app(accountId: segments[0], appId: segments[1])
        case "review" where segments.count >= 3:
            self = .review(accountId: segments[0], appId: segments[1], reviewId: segments[2])
        case "reimport" where segments.count >= 1:
            self = .reimport(accountId: segments[0])
        default:
            return nil
        }
    }

    private static func encode(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? value
    }
}
