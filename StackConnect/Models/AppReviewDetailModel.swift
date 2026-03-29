import Foundation

struct AppReviewDetailModel: Codable, Identifiable, Hashable {
    let id: String
    var contactFirstName: String?
    var contactLastName: String?
    var contactEmail: String?
    var contactPhone: String?
    var notes: String?
    var demoAccountName: String?
    var demoAccountPassword: String?
    var isDemoAccountRequired: Bool?

    init(
        id: String,
        contactFirstName: String? = nil,
        contactLastName: String? = nil,
        contactEmail: String? = nil,
        contactPhone: String? = nil,
        notes: String? = nil,
        demoAccountName: String? = nil,
        demoAccountPassword: String? = nil,
        isDemoAccountRequired: Bool? = nil
    ) {
        self.id = id
        self.contactFirstName = contactFirstName
        self.contactLastName = contactLastName
        self.contactEmail = contactEmail
        self.contactPhone = contactPhone
        self.notes = notes
        self.demoAccountName = demoAccountName
        self.demoAccountPassword = demoAccountPassword
        self.isDemoAccountRequired = isDemoAccountRequired
    }
}
