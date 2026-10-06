import Foundation

/// A Google Play app in an account's app list, either returned by the Play
/// Developer Reporting API or added manually by package name.
///
/// Phase 1 keeps Play apps out of `AppModel` / `SyncService` (plan D6): the whole
/// list is cached as one `[GooglePlayAppItem]` blob under `cacheKey(accountId:)`.
struct GooglePlayAppItem: Codable, Identifiable, Hashable {
    let id: String
    var packageName: String
    var title: String?
    var isManuallyAdded: Bool

    var displayName: String {
        title ?? packageName
    }

    /// Storage id of an account's cached Play app list (`[GooglePlayAppItem]`).
    /// Shared by the app list and `AccountCascadeDeleter`.
    static func cacheKey(accountId: String) -> String {
        "googleplay-apps.\(accountId)"
    }
}
