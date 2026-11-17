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

    /// Store icon from the app's public Google Play page (plan D18), fetched
    /// once when missing and cached with the list; `nil` until then and for apps
    /// that aren't public on Google Play (the UI shows the Play tile instead).
    /// Optional, so lists cached before icons existed still decode.
    var iconUrl: String? = nil

    var displayName: String {
        title ?? packageName
    }

    /// `iconUrl` as a `URL`, for the icon views.
    var iconURL: URL? {
        iconUrl.flatMap { URL(string: $0) }
    }

    /// Storage id of an account's cached Play app list (`[GooglePlayAppItem]`).
    /// Shared by the app list and `AccountCascadeDeleter`.
    static func cacheKey(accountId: String) -> String {
        "googleplay-apps.\(accountId)"
    }
}
