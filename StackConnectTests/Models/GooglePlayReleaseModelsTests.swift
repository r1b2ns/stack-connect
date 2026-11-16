import XCTest
import SwiftUI
import StackCoreRust
@testable import StackConnect

/// Release summaries (`releases.list`), their cache, country targeting on track
/// releases and the release action rules (plan R1, R7, R8).
final class GooglePlayReleaseModelsTests: XCTestCase {

    // MARK: - Lifecycle state

    func testLifecycleStateMapsEveryGoogleValue() {
        let expected: [String: GooglePlayReleaseLifecycleState] = [
            "RELEASE_LIFECYCLE_STATE_DRAFT": .draft,
            "RELEASE_LIFECYCLE_STATE_NOT_SENT_FOR_REVIEW": .notSentForReview,
            "RELEASE_LIFECYCLE_STATE_IN_REVIEW": .inReview,
            "RELEASE_LIFECYCLE_STATE_APPROVED_NOT_PUBLISHED": .approvedNotPublished,
            "RELEASE_LIFECYCLE_STATE_NOT_APPROVED": .notApproved,
            "RELEASE_LIFECYCLE_STATE_PUBLISHED": .published
        ]
        for (raw, state) in expected {
            XCTAssertEqual(GooglePlayReleaseLifecycleState(raw: raw), state, raw)
            XCTAssertEqual(state.rawValue, raw)
        }
    }

    func testUnknownLifecycleStateKeepsItsRawValue() throws {
        let future = GooglePlayReleaseLifecycleState(raw: "RELEASE_LIFECYCLE_STATE_SOMETHING_NEW")
        XCTAssertEqual(future, .unknown("RELEASE_LIFECYCLE_STATE_SOMETHING_NEW"))
        XCTAssertEqual(GooglePlayReleaseLifecycleState(raw: nil), .unknown(nil))
        XCTAssertEqual(future.displayName, String(localized: "Unknown"))

        let data = try JSONEncoder().encode([future, .unknown(nil), .inReview])
        let decoded = try JSONDecoder().decode([GooglePlayReleaseLifecycleState].self, from: data)
        XCTAssertEqual(decoded, [future, .unknown(nil), .inReview])
    }

    func testLifecycleStateNamesAndColors() {
        XCTAssertEqual(GooglePlayReleaseLifecycleState.draft.displayName, String(localized: "Draft"))
        XCTAssertEqual(GooglePlayReleaseLifecycleState.notSentForReview.displayName, String(localized: "Not sent for review"))
        XCTAssertEqual(GooglePlayReleaseLifecycleState.inReview.displayName, String(localized: "In review"))
        XCTAssertEqual(GooglePlayReleaseLifecycleState.approvedNotPublished.displayName, String(localized: "Approved, not published"))
        XCTAssertEqual(GooglePlayReleaseLifecycleState.notApproved.displayName, String(localized: "Not approved"))
        XCTAssertEqual(GooglePlayReleaseLifecycleState.published.displayName, String(localized: "Published"))

        XCTAssertEqual(GooglePlayReleaseLifecycleState.draft.color, .gray)
        XCTAssertEqual(GooglePlayReleaseLifecycleState.notSentForReview.color, .gray)
        XCTAssertEqual(GooglePlayReleaseLifecycleState.inReview.color, .orange)
        XCTAssertEqual(GooglePlayReleaseLifecycleState.approvedNotPublished.color, .yellow)
        XCTAssertEqual(GooglePlayReleaseLifecycleState.notApproved.color, .red)
        XCTAssertEqual(GooglePlayReleaseLifecycleState.published.color, .green)
    }

    // MARK: - Summary

    private func summary(_ name: String?, _ state: GooglePlayReleaseLifecycleState, _ codes: [String], track: String = "production") -> GooglePlayReleaseSummaryModel {
        GooglePlayReleaseSummaryModel(track: track, name: name, lifecycleState: state, versionCodes: codes)
    }

    func testShortNameDropsPlayConsolesVersionCodeSuffix() {
        XCTAssertEqual(summary(nil, .published, ["4210"]).shortName, "4210")
        XCTAssertEqual(summary("4.2.0 (4210)", .published, ["4210"]).shortName, "4.2.0")
        XCTAssertEqual(summary("4.2.0 (9999)", .published, ["4210"]).shortName, "4.2.0 (9999)", "Only the release's own code is dropped")
        XCTAssertEqual(summary("Spring release", .published, ["4210"]).shortName, "Spring release")
        XCTAssertEqual(summary("  ", .published, []).shortName, String(localized: "Untitled release"))
    }

    func testHeadlinePrefersTheReleaseThatNeedsAttentionThenTheNewest() {
        let published = summary("4.1.0 (410)", .published, ["410"])
        let newerPublished = summary("4.2.0 (420)", .published, ["420"])
        let inReview = summary("4.3.0 (430)", .inReview, ["430"])
        let rejected = summary("4.0.9 (409)", .notApproved, ["409"])

        XCTAssertEqual(GooglePlayReleaseSummaryModel.headline(of: [published, newerPublished]), newerPublished)
        XCTAssertEqual(GooglePlayReleaseSummaryModel.headline(of: [published, inReview]), inReview)
        XCTAssertEqual(GooglePlayReleaseSummaryModel.headline(of: [inReview, rejected, published]), rejected)
        XCTAssertNil(GooglePlayReleaseSummaryModel.headline(of: []))
    }

    func testReleaseKeyIsTrackPlusSortedVersionCodes() {
        let summaryKey = summary("x", .published, ["20", "10"]).releaseKey
        let release = GooglePlayReleaseModel(name: "x", status: .completed, versionCodes: ["10", "20"], userFraction: nil, releaseNotes: [], inAppUpdatePriority: nil)
        XCTAssertEqual(summaryKey, release.releaseKey(track: "production"))
        XCTAssertNotEqual(summaryKey, release.releaseKey(track: "beta"))
    }

    // MARK: - Cache

    func testCacheKeyAndTrackGrouping() {
        let cache = GooglePlayReleaseSummariesCache(
            accountId: "acc",
            packageName: "com.example.app",
            summaries: [
                summary("1.1", .draft, ["11"], track: "internal"),
                summary("1.0", .published, ["10"], track: "production"),
                summary("1.0.1", .inReview, ["12"], track: "production"),
                summary("1.1-beta", .published, ["13"], track: "beta")
            ],
            fetchedAt: nil
        )

        XCTAssertEqual(cache.cacheKey, "googleplay-releases.acc.com.example.app")
        XCTAssertEqual(cache.tracks.map(\.track), ["production", "beta", "internal"])
        XCTAssertEqual(cache.tracks.first?.releases.map(\.versionCodes), [["12"], ["10"]], "Newest first")
    }

    func testCacheRoundTripsThroughJSON() throws {
        let cache = GooglePlayReleaseSummariesCache(
            accountId: "acc", packageName: "p",
            summaries: [summary("1.0", .unknown("NEW_STATE"), ["10"], track: "production")],
            fetchedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let decoded = try JSONDecoder().decode(GooglePlayReleaseSummariesCache.self, from: JSONEncoder().encode(cache))
        XCTAssertEqual(decoded.summaries, cache.summaries)
        XCTAssertEqual(decoded.fetchedAt, cache.fetchedAt)
    }

    // MARK: - Country targeting

    func testTracksCacheWrittenBeforeCountryTargetingStillDecodes() throws {
        let json = #"""
        {"accountId":"acc","packageName":"p","tracks":[{"track":"production","releases":[
          {"name":"1.0","status":"completed","versionCodes":["10"],"releaseNotes":[]}
        ]}]}
        """#
        let cache = try JSONDecoder().decode(GooglePlayTracksCache.self, from: Data(json.utf8))
        XCTAssertNil(cache.tracks.first?.releases.first?.countryTargeting)
    }

    func testMappingCarriesCountryTargetingAndLifecycle() {
        let release = GooglePlayAccountConnection.mapRelease(StackCoreRust.TrackReleaseInfo(
            name: "2.0.0 (200)", status: "completed", versionCodes: ["200"], userFraction: nil, releaseNotes: [],
            inAppUpdatePriority: nil, countryTargeting: CountryTargetingInfo(countries: ["US", "CA"], includeRestOfWorld: false)
        ))
        XCTAssertEqual(release.countryTargeting, GooglePlayCountryTargetingModel(countries: ["US", "CA"], includeRestOfWorld: false))

        let summary = GooglePlayAccountConnection.mapReleaseSummary(StackCoreRust.ReleaseSummaryInfo(
            track: "beta", name: nil, lifecycleState: "RELEASE_LIFECYCLE_STATE_IN_REVIEW", versionCodes: ["7"]
        ))
        XCTAssertEqual(summary, GooglePlayReleaseSummaryModel(track: "beta", name: nil, lifecycleState: .inReview, versionCodes: ["7"]))
        XCTAssertEqual(summary.trackKind, .openTesting)
    }

    // MARK: - Release actions (R8)

    private let kinds: [GooglePlayTrackKind] = [.production, .openTesting, .closedTesting, .internalTesting, .custom("qa")]
    private let states: [GooglePlayReleaseLifecycleState?] = [nil, .draft, .notSentForReview, .inReview, .approvedNotPublished, .published, .unknown("X")]

    func testStagedRolloutOnlyOnProductionAndOpenTesting() {
        XCTAssertEqual(kinds.filter(GooglePlayReleaseActions.supportsStagedRollout), [.production, .openTesting])
    }

    /// Full matrix: track kind × status × lifecycle state (not approved is
    /// covered separately).
    func testActionMatrix() {
        for kind in kinds {
            let staged = GooglePlayReleaseActions.supportsStagedRollout(kind)
            for state in states {
                func actions(_ status: GooglePlayReleaseStatus, _ fraction: Double?) -> [GooglePlayReleaseAction] {
                    GooglePlayReleaseActions.actions(trackKind: kind, status: status, userFraction: fraction, lifecycleState: state)
                }
                let context = "\(kind) / \(String(describing: state))"
                XCTAssertEqual(actions(.draft, nil), [.rollOut], context)
                XCTAssertEqual(actions(.inProgress, 0.2), staged ? [.increaseRollout, .halt, .releaseToAll] : [.halt, .releaseToAll], context)
                XCTAssertEqual(actions(.inProgress, nil), [.halt, .releaseToAll], "No fraction, nothing to increase: \(context)")
                XCTAssertEqual(actions(.halted, 0.1), [.resume, .releaseToAll], context)
                XCTAssertEqual(actions(.completed, nil), kind == .production ? [] : [.promote], context)
                XCTAssertEqual(actions(.unknown, nil), [], context)
            }
        }
    }

    func testNotApprovedReleaseOffersNothing() {
        for kind in kinds {
            for status in [GooglePlayReleaseStatus.draft, .inProgress, .halted, .completed, .unknown] {
                XCTAssertEqual(
                    GooglePlayReleaseActions.actions(trackKind: kind, status: status, userFraction: 0.5, lifecycleState: .notApproved),
                    [], "\(kind) / \(status)"
                )
            }
        }
    }

    func testActionsForATrackRelease() {
        let release = GooglePlayReleaseModel(name: "1", status: .inProgress, versionCodes: ["1"], userFraction: 0.5, releaseNotes: [], inAppUpdatePriority: nil)
        XCTAssertEqual(GooglePlayReleaseActions.actions(for: release, on: .production, lifecycleState: .published), [.increaseRollout, .halt, .releaseToAll])
    }
}
