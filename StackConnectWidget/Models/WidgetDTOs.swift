import Foundation

// MARK: - DTOs
//
// Focused, decode-only mirrors of the app's domain models. They decode the same
// JSON payloads the app persists into the shared SwiftData store, but expose only
// the fields the widgets render. Stored under the app's original type names
// ("AppModel", "CustomerReviewModel", "PhasedReleaseModel").

struct WidgetApp: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    var iconUrl: String?
    var appStoreState: String?
    var versionString: String?
    var lastModifiedDate: Date?
    var isArchived: Bool?
    var platform: String?
    var platformVersions: [WidgetPlatformVersion]?

    /// Cached icon bytes from the shared App Group container. Not part of the
    /// persisted JSON — populated by `WidgetDataLoader` after decoding.
    var iconData: Data?

    private enum CodingKeys: String, CodingKey {
        case id, name, iconUrl, appStoreState, versionString, lastModifiedDate, isArchived, platform, platformVersions
    }
}

struct WidgetPlatformVersion: Codable, Hashable {
    let platform: String
    var appStoreState: String?
    var versionString: String?
}

struct WidgetReview: Codable, Identifiable, Hashable {
    let id: String
    var rating: Int
    var title: String?
    var body: String?
    var createdDate: Date?
    var responseBody: String?
    var appId: String?

    var hasResponse: Bool {
        guard let responseBody else { return false }
        return !responseBody.isEmpty
    }
}

struct WidgetPhasedRelease: Codable, Hashable {
    let id: String
    var state: String?
    var currentDayNumber: Int?
}

// MARK: - Combined Review Item

struct WidgetReviewItem: Identifiable, Hashable {
    let review: WidgetReview
    let app: WidgetApp
    var id: String { review.id }
}
