import Foundation

struct AppInfoModel: Codable, Identifiable, Hashable {
    let id: String          // appInfo id
    let appId: String
    var sku: String?
    var primaryLocale: String?
    var contentRightsDeclaration: String?
    var primaryCategoryId: String?
    var primaryCategoryName: String?
    var primarySubcategoryOneId: String?
    var primarySubcategoryOneName: String?
    var secondaryCategoryId: String?
    var secondaryCategoryName: String?
    var secondarySubcategoryOneId: String?
    var ageRatingDeclarationId: String?
    var appStoreAgeRating: String?
    // Localizations
    var localizations: [AppInfoLocalizationModel] = []
}

struct AppInfoLocalizationModel: Codable, Identifiable, Hashable {
    let id: String
    var locale: String
    var name: String?
    var subtitle: String?
    var privacyPolicyUrl: String?
    var privacyChoicesUrl: String?
    var privacyPolicyText: String?
}
