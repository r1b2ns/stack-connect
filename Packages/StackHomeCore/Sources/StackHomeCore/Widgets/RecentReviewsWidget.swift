import Foundation
import StackProtocols

/// Typed result produced by the Recent Reviews widget's `load()` (US-007 AC-4).
///
/// Foundation-pure (US-010): no SwiftUI. Carries up to 5 resolved reviews
/// (TC-035/TC-036) plus the accounts map for tap routing.
public struct RecentReviewsWidgetData: Hashable, Sendable {
    /// The most-recent reviews across active apps, capped at 5 (TC-035/TC-036).
    public var reviews: [HomeRecentReview]
    /// Accounts keyed by id, for resolving each review's owning account on tap.
    public var accountsMap: [String: AccountModel]

    public init(reviews: [HomeRecentReview] = [], accountsMap: [String: AccountModel] = [:]) {
        self.reviews = reviews
        self.accountsMap = accountsMap
    }
}

/// Loads the data backing the "Recent Reviews" Home widget (US-007 AC-4).
///
/// Foundation-pure (US-010 AC-1/AC-5): no view code, no `makeView()`. Caps the
/// result at the 5 most-recent reviews (TC-035/TC-036).
@MainActor
public final class RecentReviewsWidget: HomeWidget {

    /// Maximum number of reviews surfaced by the widget (TC-035/TC-036).
    public static let maxReviews = 5

    public static let kind: HomeWidgetKind = .recentReviews

    public let configuration: HomeWidgetConfiguration

    public private(set) var data = RecentReviewsWidgetData()
    public private(set) var isLoading: Bool = false

    private let storage: PersistentStorable

    public init(configuration: HomeWidgetConfiguration, storage: PersistentStorable) {
        self.configuration = configuration
        self.storage = storage
    }

    public func load() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let allApps: [AppModel] = try await storage.fetchAll(AppModel.self)
            // Exclude archived apps so their reviews never appear in the widget.
            let active = allApps.filter { !$0.isArchived }
            let appById = Dictionary(uniqueKeysWithValues: active.map { ($0.id, $0) })
            let allReviews: [CustomerReviewModel] = try await storage.fetchAll(CustomerReviewModel.self)
            let reviews = allReviews
                .compactMap { review -> HomeRecentReview? in
                    guard let appId = review.appId, let app = appById[appId] else { return nil }
                    return HomeRecentReview(review: review, app: app)
                }
                .sorted { (a, b) in
                    (a.review.createdDate ?? .distantPast) > (b.review.createdDate ?? .distantPast)
                }
                .prefix(Self.maxReviews)
                .map { $0 }
            data = RecentReviewsWidgetData(
                reviews: reviews,
                accountsMap: await HomeWidgetDataLoader.loadAccounts(storage: storage)
            )
        } catch {
            HomeWidgetLog.error("[Widget][RecentReviews] Failed to load reviews: \(error.localizedDescription)")
            data = RecentReviewsWidgetData()
        }
    }
}
