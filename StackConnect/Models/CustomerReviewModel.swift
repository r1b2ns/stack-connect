import Foundation

struct CustomerReviewModel: Codable, Identifiable, Hashable {
    let id: String
    var rating: Int
    var title: String?
    var body: String?
    var reviewerNickname: String?
    var createdDate: Date?
    var territory: String?
    var responseId: String?
    var responseBody: String?
    var responseState: String?
    var responseDate: Date?
    /// Set by SyncService when caching reviews so the Home dashboard can group by app.
    /// Not populated by the API mapping itself.
    var appId: String?

    var hasResponse: Bool {
        responseBody != nil && !responseBody!.isEmpty
    }

    var territoryDisplayName: String {
        guard let territory else { return "–" }
        return Locale.current.localizedString(forRegionCode: territory) ?? territory
    }
}

extension CustomerReviewModel {
    /// Storage id of a review cached for the Home dashboard, for both stores:
    /// `review.{appId}.{reviewId}` (`appId` is the App Store app id or the Play
    /// package name, plan H4).
    static func storageId(appId: String, reviewId: String) -> String {
        "review.\(appId).\(reviewId)"
    }
}
