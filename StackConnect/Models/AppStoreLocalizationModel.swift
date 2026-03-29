import Foundation

struct AppStoreLocalizationModel: Codable, Identifiable, Hashable {
    let id: String
    var locale: String?
    var description: String?
    var keywords: String?
    var promotionalText: String?
    var supportUrl: String?
    var marketingUrl: String?
    var whatsNew: String?

    init(
        id: String,
        locale: String? = nil,
        description: String? = nil,
        keywords: String? = nil,
        promotionalText: String? = nil,
        supportUrl: String? = nil,
        marketingUrl: String? = nil,
        whatsNew: String? = nil
    ) {
        self.id = id
        self.locale = locale
        self.description = description
        self.keywords = keywords
        self.promotionalText = promotionalText
        self.supportUrl = supportUrl
        self.marketingUrl = marketingUrl
        self.whatsNew = whatsNew
    }
}
