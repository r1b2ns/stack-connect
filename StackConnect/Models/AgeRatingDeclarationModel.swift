import Foundation

struct AgeRatingDeclarationModel: Codable, Identifiable, Hashable {
    let id: String

    var alcoholTobaccoOrDrugUseOrReferences: String?
    var contests: String?
    var gamblingSimulated: String?
    var gunsOrOtherWeapons: String?
    var medicalOrTreatmentInformation: String?
    var profanityOrCrudeHumor: String?
    var sexualContentGraphicAndNudity: String?
    var sexualContentOrNudity: String?
    var horrorOrFearThemes: String?
    var matureOrSuggestiveThemes: String?
    var violenceCartoonOrFantasy: String?
    var violenceRealistic: String?
    var violenceRealisticProlongedGraphicOrSadistic: String?
    var isAdvertising: Bool?
    var isGambling: Bool?
    var isUnrestrictedWebAccess: Bool?
    var isUserGeneratedContent: Bool?
    var ageRatingOverrideV2: String?
}

enum AgeRatingLevel: String, Codable, CaseIterable, Hashable {
    case none = "NONE"
    case infrequentOrMild = "INFREQUENT_OR_MILD"
    case frequentOrIntense = "FREQUENT_OR_INTENSE"

    var displayName: String {
        switch self {
        case .none:             return String(localized: "None")
        case .infrequentOrMild: return String(localized: "Infrequent or Mild")
        case .frequentOrIntense: return String(localized: "Frequent or Intense")
        }
    }
}

enum AgeRatingOverrideV2: String, Codable, CaseIterable, Hashable {
    case none = "NONE"
    case nineplus = "9PLUS"
    case thirteenplus = "13PLUS"
    case sixteenplus = "16PLUS"
    case eighteenplus = "18PLUS"

    var displayName: String {
        switch self {
        case .none:         return String(localized: "None")
        case .nineplus:     return "9+"
        case .thirteenplus: return "13+"
        case .sixteenplus:  return "16+"
        case .eighteenplus: return "18+"
        }
    }
}
