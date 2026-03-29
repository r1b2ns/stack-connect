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

    var hasResponse: Bool {
        responseBody != nil && !responseBody!.isEmpty
    }

    var territoryDisplayName: String {
        guard let territory else { return "–" }
        return Locale.current.localizedString(forRegionCode: territory) ?? territory
    }
}
