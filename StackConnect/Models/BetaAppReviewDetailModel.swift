import Foundation

struct BetaAppReviewDetailModel: Codable, Identifiable, Hashable {
    let id: String
    var contactFirstName: String?
    var contactLastName: String?
    var contactEmail: String?
    var contactPhone: String?
    var demoAccountName: String?
    var demoAccountPassword: String?
    var isDemoAccountRequired: Bool?
    var notes: String?

    init(
        id: String,
        contactFirstName: String? = nil,
        contactLastName: String? = nil,
        contactEmail: String? = nil,
        contactPhone: String? = nil,
        demoAccountName: String? = nil,
        demoAccountPassword: String? = nil,
        isDemoAccountRequired: Bool? = nil,
        notes: String? = nil
    ) {
        self.id = id
        self.contactFirstName = contactFirstName
        self.contactLastName = contactLastName
        self.contactEmail = contactEmail
        self.contactPhone = contactPhone
        self.demoAccountName = demoAccountName
        self.demoAccountPassword = demoAccountPassword
        self.isDemoAccountRequired = isDemoAccountRequired
        self.notes = notes
    }
}

struct BetaAppLocalizationModel: Codable, Identifiable, Hashable {
    let id: String
    var locale: String
    var feedbackEmail: String?
    var description: String?

    init(
        id: String,
        locale: String,
        feedbackEmail: String? = nil,
        description: String? = nil
    ) {
        self.id = id
        self.locale = locale
        self.feedbackEmail = feedbackEmail
        self.description = description
    }
}
