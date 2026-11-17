import Foundation

/// Store details of a Google Play app (Android Publisher `edits.details`): the
/// default store-listing language and the public contact details. Read-only.
struct GooglePlayAppDetailsModel: Codable, Hashable {
    let packageName: String
    /// BCP-47 code of the default store listing (e.g. `en-US`).
    var defaultLanguage: String?
    var contactEmail: String?
    var contactPhone: String?
    var contactWebsite: String?
}
