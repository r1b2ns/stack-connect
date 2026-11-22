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

    /// Pinned to the top of the app list ("Favorites"), like `AppModel.isFavorite`.
    /// Kept across syncs by `GooglePlayAppListSync.merge`.
    var isFavorite: Bool = false

    /// Hidden from the app list, the Home widgets and the background sync's
    /// release status / reviews; listed under "Archived Apps" instead, like
    /// `AppModel.isArchived`. Kept across syncs by `GooglePlayAppListSync.merge`.
    var isArchived: Bool = false

    private enum CodingKeys: String, CodingKey {
        case id, packageName, title, isManuallyAdded, iconUrl, isFavorite, isArchived
    }

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

// MARK: - Codable

extension GooglePlayAppItem {
    /// Custom decoding (in an extension, so the memberwise init stays) because
    /// synthesized decoding requires every non-optional key: lists cached before
    /// `isFavorite` / `isArchived` existed must still decode (as `false`), or the
    /// whole cached list would be lost.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        packageName = try container.decode(String.self, forKey: .packageName)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        isManuallyAdded = try container.decode(Bool.self, forKey: .isManuallyAdded)
        iconUrl = try container.decodeIfPresent(String.self, forKey: .iconUrl)
        isFavorite = try container.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
        isArchived = try container.decodeIfPresent(Bool.self, forKey: .isArchived) ?? false
    }
}
