import Foundation
import StackProtocols

/// Result of resolving a customer review against the app it belongs to.
///
/// Foundation-pure result type (US-010): the data the Recent Reviews widget
/// produces. The platform view layers (iOS `HomeReviewRowView`, Windows
/// `WindowsRecentReviewsWidgetView`) render from this; it carries no SwiftUI.
public struct HomeRecentReview: Identifiable, Hashable, Sendable {
    public let review: CustomerReviewModel
    public let app: AppModel
    public var id: String { review.id }

    public init(review: CustomerReviewModel, app: AppModel) {
        self.review = review
        self.app = app
    }
}

/// Shared, Foundation-pure data-loading helpers for the Home widgets.
///
/// Holds only the logic exercised by the widgets' `load()` pipelines
/// (accounts map, phased releases, recency sort, account lookup). View-only
/// grouping helpers that depend on Apple-only iconography stay in the iOS app
/// target.
public enum HomeWidgetDataLoader {

    /// Loads all accounts keyed by id, filling any missing expiration rules.
    public static func loadAccounts(storage: PersistentStorable) async -> [String: AccountModel] {
        do {
            let accounts: [AccountModel] = try await storage.fetchAll(AccountModel.self)
            var map: [String: AccountModel] = [:]
            for var account in accounts {
                account.fillMissingRules()
                map[account.id] = account
            }
            return map
        } catch {
            HomeWidgetLog.error("[Widget] Failed to load accounts: \(error.localizedDescription)")
            return [:]
        }
    }

    /// Loads the phased-release record (if any) for each app, keyed by app id.
    public static func loadPhasedReleases(
        for apps: [AppModel],
        storage: PersistentStorable
    ) async -> [String: PhasedReleaseModel] {
        var result: [String: PhasedReleaseModel] = [:]
        for app in apps {
            if let phased: PhasedReleaseModel = try? await storage.fetch(PhasedReleaseModel.self, id: "phased.\(app.id)") {
                result[app.id] = phased
            }
        }
        return result
    }

    /// Sorts apps by most-recently-modified, falling back to name.
    public static func sortByRecency(_ a: AppModel, _ b: AppModel) -> Bool {
        switch (a.lastModifiedDate, b.lastModifiedDate) {
        case let (dateA?, dateB?): return dateA > dateB
        case (_?, nil):            return true
        case (nil, _?):            return false
        case (nil, nil):           return a.name < b.name
        }
    }

    /// Resolves the account an app belongs to, with a safe fallback.
    public static func account(for app: AppModel, in map: [String: AccountModel]) -> AccountModel {
        map[app.accountId] ?? AccountModel(id: app.accountId, name: "", providerType: .apple)
    }
}
