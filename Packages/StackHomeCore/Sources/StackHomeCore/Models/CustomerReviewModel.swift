import Foundation

public struct CustomerReviewModel: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public var rating: Int
    public var title: String?
    public var body: String?
    public var reviewerNickname: String?
    public var createdDate: Date?
    public var territory: String?
    public var responseId: String?
    public var responseBody: String?
    public var responseState: String?
    public var responseDate: Date?
    /// Set by SyncService when caching reviews so the Home dashboard can group by app.
    /// Not populated by the API mapping itself.
    public var appId: String?

    public init(
        id: String,
        rating: Int,
        title: String? = nil,
        body: String? = nil,
        reviewerNickname: String? = nil,
        createdDate: Date? = nil,
        territory: String? = nil,
        responseId: String? = nil,
        responseBody: String? = nil,
        responseState: String? = nil,
        responseDate: Date? = nil,
        appId: String? = nil
    ) {
        self.id = id
        self.rating = rating
        self.title = title
        self.body = body
        self.reviewerNickname = reviewerNickname
        self.createdDate = createdDate
        self.territory = territory
        self.responseId = responseId
        self.responseBody = responseBody
        self.responseState = responseState
        self.responseDate = responseDate
        self.appId = appId
    }

    public var hasResponse: Bool {
        responseBody != nil && !responseBody!.isEmpty
    }

    public var territoryDisplayName: String {
        guard let territory else { return "–" }
        return Locale.current.localizedString(forRegionCode: territory) ?? territory
    }
}
