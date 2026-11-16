#if DEBUG
import Foundation

// Declarative description of the fake App Store Connect content.
// `FakeAppStoreConnectCatalog` expands these seeds into a coherent
// `FakeAppStoreConnectState` (versions ↔ builds ↔ submissions ↔ TestFlight).

struct FakeASCTeamSeed: Sendable {
    let issuerId: String
    let name: String
    /// Apple Developer team ID (10 characters), the App ID prefix.
    let teamId: String
    let apps: [FakeASCAppSeed]
    let people: [FakeASCPersonSeed]
    let devices: [FakeASCDeviceSeed]
    let certificates: [FakeASCCertificateSeed]
}

struct FakeASCAppSeed: Sendable {
    let id: String
    let name: String
    let bundleId: String
    let sku: String
    let symbol: String
    let color: String
    let primaryCategory: String
    var primarySubcategory: String? = nil
    var secondaryCategory: String? = nil
    var appStoreAgeRating = "FOUR_PLUS"
    /// Age rating answers that are not "NONE" (field name → value).
    var ageRatingAnswers: [String: String] = [:]
    var hasIPad = true
    let versions: [FakeASCVersionSeed]
    /// Store text per locale; the first entry is the primary locale.
    let texts: [(locale: String, text: FakeASCLocalizedText)]
    let screenshotCaptions: [String]
    let reviews: [FakeASCReviewSeed]
    var testFlight: FakeASCTestFlightSeed? = nil
    var capabilities: [String] = []
    /// App Store ratings per storefront (country → (average, count)) for the
    /// rating summary above the reviews.
    var storefrontRatings: [String: (Double, Int)] = [:]
}

struct FakeASCLocalizedText: Sendable {
    let name: String
    let subtitle: String
    let description: String
    let keywords: String
    let promotionalText: String
    /// "What's New" of the newest version (older versions get generic notes).
    let whatsNew: String
}

struct FakeASCVersionSeed: Sendable {
    let platform: String
    let version: String
    /// `appStoreState` raw value.
    let state: String
    /// Days since the version was created.
    let createdDaysAgo: Double
    /// Build number attached to the version.
    let build: String
    var releaseType = "AFTER_APPROVAL"
    /// Day N of an ACTIVE 7-day phased release.
    var phasedDay: Int? = nil
    /// Days since it was submitted for review (`nil` = never submitted).
    var submittedDaysAgo: Double? = nil
}

struct FakeASCReviewSeed: Sendable {
    let rating: Int32
    let title: String
    let body: String
    let nickname: String
    let territory: String
    let daysAgo: Double
    var reply: String? = nil
    var replyPending = false
}

struct FakeASCTestFlightSeed: Sendable {
    /// Marketing version of the builds in beta.
    let version: String
    /// Build numbers, oldest first. The last one is still processing.
    let builds: [String]
    let whatToTest: String
    let externalGroupName: String
}

struct FakeASCPersonSeed: Sendable {
    let firstName: String
    let lastName: String
    let email: String
    let roles: [String]
    var allAppsVisible = true
    var provisioningAllowed = false
    var isPending = false
    /// Apps visible when `allAppsVisible` is false (seed app ids).
    var visibleAppIds: [String] = []
    /// Also a TestFlight internal tester.
    var isTester = true
}

struct FakeASCDeviceSeed: Sendable {
    let name: String
    let platform: String
    let deviceClass: String
    let model: String
    var status = "ENABLED"
    let addedDaysAgo: Double
}

struct FakeASCCertificateSeed: Sendable {
    let type: String
    let owner: String
    /// Positive: expires in N days; negative would be expired.
    let expiresInDays: Double
}
#endif
