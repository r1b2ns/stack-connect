import Foundation

/// One localized Google Play store listing (Android Publisher `edits.listings`).
/// Read-only.
struct GooglePlayStoreListingModel: Codable, Hashable, Identifiable {
    /// BCP-47 language code (e.g. `en-US`). Unique per app.
    let language: String
    var title: String?
    var shortDescription: String?
    var fullDescription: String?
    /// Promo video URL (YouTube), when set.
    var video: String?

    var id: String { language }

    /// Display order: the default language first, then the rest by their
    /// localized name. `defaultLanguage` comes from the cached app details and
    /// may be unknown (`nil`), in which case only the name order applies.
    static func sorted(_ listings: [GooglePlayStoreListingModel], defaultLanguage: String?) -> [GooglePlayStoreListingModel] {
        listings.sorted { lhs, rhs in
            let lhsIsDefault = lhs.isLanguage(defaultLanguage)
            let rhsIsDefault = rhs.isLanguage(defaultLanguage)
            if lhsIsDefault != rhsIsDefault {
                return lhsIsDefault
            }
            return GooglePlayLanguage.displayName(for: lhs.language)
                .localizedCaseInsensitiveCompare(GooglePlayLanguage.displayName(for: rhs.language)) == .orderedAscending
        }
    }

    /// Case-insensitive match against a language code (`en-US` == `en-us`).
    func isLanguage(_ code: String?) -> Bool {
        guard let code else { return false }
        return language.caseInsensitiveCompare(code) == .orderedSame
    }
}

/// Display helpers for the BCP-47 language codes Google Play uses.
enum GooglePlayLanguage {

    /// Localized language name (e.g. `en-US` → "English (United States)"),
    /// falling back to the raw code when the system doesn't know it.
    static func displayName(for code: String, locale: Locale = .current) -> String {
        locale.localizedString(forIdentifier: code) ?? code
    }
}
