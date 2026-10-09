import XCTest
@testable import StackConnect

final class GooglePlayAppModelsTests: XCTestCase {

    // MARK: - App list item

    func testAppItemCachedBeforeIconsExistedStillDecodes() throws {
        // The exact shape lists were cached in before `iconUrl` was added.
        let json = #"[{"id":"com.a","packageName":"com.a","title":"A","isManuallyAdded":false},{"id":"com.b","packageName":"com.b","isManuallyAdded":true}]"#

        let items = try JSONDecoder().decode([GooglePlayAppItem].self, from: Data(json.utf8))

        XCTAssertEqual(items, [
            GooglePlayAppItem(id: "com.a", packageName: "com.a", title: "A", isManuallyAdded: false),
            GooglePlayAppItem(id: "com.b", packageName: "com.b", title: nil, isManuallyAdded: true)
        ])
        XCTAssertTrue(items.allSatisfy { $0.iconUrl == nil && $0.iconURL == nil })
    }

    func testAppItemIconSurvivesACacheRoundTrip() throws {
        let item = GooglePlayAppItem(
            id: "com.a",
            packageName: "com.a",
            title: "A",
            isManuallyAdded: false,
            iconUrl: "https://play-lh.googleusercontent.com/abc=s512"
        )

        let decoded = try JSONDecoder().decode(GooglePlayAppItem.self, from: JSONEncoder().encode(item))

        XCTAssertEqual(decoded, item)
        XCTAssertEqual(decoded.iconURL, URL(string: "https://play-lh.googleusercontent.com/abc=s512"))
    }

    // MARK: - Tracks

    func testTrackKindsFollowPlayConsoleNames() {
        XCTAssertEqual(GooglePlayTrackKind(track: "production"), .production)
        XCTAssertEqual(GooglePlayTrackKind(track: "beta"), .openTesting)
        XCTAssertEqual(GooglePlayTrackKind(track: "alpha"), .closedTesting)
        XCTAssertEqual(GooglePlayTrackKind(track: "internal"), .internalTesting)
        XCTAssertEqual(GooglePlayTrackKind(track: "qa-team"), .custom("qa-team"))
        XCTAssertEqual(GooglePlayTrackKind(track: "qa-team").displayName, "qa-team")
    }

    func testTracksSortProductionTestingThenCustomByName() {
        let names = ["zeta", "internal", "Alpha-custom", "alpha", "production", "beta"]
        let sorted = GooglePlayTrackModel.sorted(names.map { GooglePlayTrackModel(track: $0, releases: []) })

        XCTAssertEqual(sorted.map(\.track), ["production", "beta", "alpha", "internal", "Alpha-custom", "zeta"])
    }

    func testRolloutFractionOnlyWhileRollingOutOrHalted() {
        func release(_ status: GooglePlayReleaseStatus) -> GooglePlayReleaseModel {
            GooglePlayReleaseModel(name: nil, status: status, versionCodes: [], userFraction: 0.1, releaseNotes: [], inAppUpdatePriority: nil)
        }

        XCTAssertEqual(release(.inProgress).rolloutFraction, 0.1)
        XCTAssertEqual(release(.halted).rolloutFraction, 0.1)
        XCTAssertNil(release(.completed).rolloutFraction)
        XCTAssertNil(release(.draft).rolloutFraction)
    }

    func testReleaseDisplayNameFallsBack() {
        let named = GooglePlayReleaseModel(name: "2.0 (20)", status: .draft, versionCodes: ["20"], userFraction: nil, releaseNotes: [], inAppUpdatePriority: nil)
        let unnamed = GooglePlayReleaseModel(name: "  ", status: .draft, versionCodes: ["20", "21"], userFraction: nil, releaseNotes: [], inAppUpdatePriority: nil)
        let empty = GooglePlayReleaseModel(name: nil, status: .draft, versionCodes: [], userFraction: nil, releaseNotes: [], inAppUpdatePriority: nil)

        XCTAssertEqual(named.displayName, "2.0 (20)")
        XCTAssertEqual(unnamed.displayName, "20, 21")
        XCTAssertEqual(empty.displayName, String(localized: "Untitled release"))
    }

    // MARK: - Store listings

    func testListingsPutTheDefaultLanguageFirstCaseInsensitively() {
        let listings = ["fr-FR", "en-US", "de-DE"].map {
            GooglePlayStoreListingModel(language: $0, title: nil, shortDescription: nil, fullDescription: nil, video: nil)
        }

        let sorted = GooglePlayStoreListingModel.sorted(listings, defaultLanguage: "EN-us")

        XCTAssertEqual(sorted.first?.language, "en-US")
        XCTAssertEqual(Set(sorted.dropFirst().map(\.language)), ["fr-FR", "de-DE"])
    }

    func testListingsWithoutADefaultLanguageAreSortedByName() {
        let listings = ["fr-FR", "de-DE"].map {
            GooglePlayStoreListingModel(language: $0, title: nil, shortDescription: nil, fullDescription: nil, video: nil)
        }
        let english = Locale(identifier: "en")
        let expected = listings
            .map(\.language)
            .sorted {
                GooglePlayLanguage.displayName(for: $0).localizedCaseInsensitiveCompare(GooglePlayLanguage.displayName(for: $1)) == .orderedAscending
            }

        XCTAssertEqual(GooglePlayStoreListingModel.sorted(listings, defaultLanguage: nil).map(\.language), expected)
        XCTAssertEqual(GooglePlayLanguage.displayName(for: "de-DE", locale: english), "German (Germany)")
    }

    // MARK: - Cache keys

    /// Storage ids are persisted on devices: they must stay stable.
    func testCacheKeysAreStableAndDistinctPerSection() {
        XCTAssertEqual(GooglePlayAppDetailsCache.cacheKey(accountId: "a", packageName: "p"), "googleplay-details.a.p")
        XCTAssertEqual(GooglePlayStoreListingsCache.cacheKey(accountId: "a", packageName: "p"), "googleplay-listings.a.p")
        XCTAssertEqual(GooglePlayTracksCache.cacheKey(accountId: "a", packageName: "p"), "googleplay-tracks.a.p")
        XCTAssertEqual(GooglePlayReviewsCache.cacheKey(accountId: "a", packageName: "p"), "googleplay-reviews.a.p")
        XCTAssertNotEqual(GooglePlayAppItem.cacheKey(accountId: "a"), GooglePlayAppDetailsCache.cacheKey(accountId: "a", packageName: ""))
    }
}
