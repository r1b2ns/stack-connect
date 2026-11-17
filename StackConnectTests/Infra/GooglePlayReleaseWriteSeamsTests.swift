import XCTest
import StackCoreRust
@testable import StackConnect

/// The write half of the Google Play release seams (plan T1 write part, T8):
/// app → core mapping, the offline guard, error copy, the write access policy
/// and the `googlePlayReleaseWrites` flag.
final class GooglePlayReleaseWriteSeamsTests: XCTestCase {

    private let app = GooglePlayAppItem(id: "com.example.app", packageName: "com.example.app", title: "Example", isManuallyAdded: false)

    override func tearDown() {
        FeatureFlags.sessionDefaults = [:]
        super.tearDown()
    }

    // MARK: - Mapping

    func testSimpleChangesMapToTheCoreCases() {
        XCTAssertEqual(GooglePlayAccountConnection.coreChange(.setRollout(versionCodes: ["42"], userFraction: 0.2)),
                       .setRollout(versionCodes: ["42"], userFraction: 0.2))
        XCTAssertEqual(GooglePlayAccountConnection.coreChange(.halt(versionCodes: ["42"])), .halt(versionCodes: ["42"]))
        XCTAssertEqual(GooglePlayAccountConnection.coreChange(.resume(versionCodes: ["42"])), .resume(versionCodes: ["42"]))
        XCTAssertEqual(GooglePlayAccountConnection.coreChange(.complete(versionCodes: ["42"])), .complete(versionCodes: ["42"]))
    }

    func testMetadataUpdateKeepsNilFieldsUnchanged() {
        let change = GooglePlayReleaseChange.updateMetadata(
            versionCodes: ["42"],
            update: GooglePlayReleaseMetadataUpdate(name: "4.2.0", releaseNotes: nil, inAppUpdatePriority: 3)
        )

        XCTAssertEqual(
            GooglePlayAccountConnection.coreChange(change),
            .updateMetadata(versionCodes: ["42"], update: ReleaseMetadataUpdate(name: "4.2.0", releaseNotes: nil, inAppUpdatePriority: 3, countryTargeting: nil))
        )
    }

    func testCreateAndPromoteMapStatusNotesAndPriority() {
        let notes = [GooglePlayLocalizedTextModel(language: "en-US", text: "Fixes")]
        let create = GooglePlayReleaseChange.create(GooglePlayNewRelease(
            versionCodes: ["43"], name: "4.3.0", releaseNotes: notes, status: .inProgress(userFraction: 0.1), inAppUpdatePriority: nil
        ))
        XCTAssertEqual(
            GooglePlayAccountConnection.coreChange(create),
            .createRelease(release: NewRelease(
                versionCodes: ["43"], name: "4.3.0",
                releaseNotes: [LocalizedTextInfo(language: "en-US", text: "Fixes")],
                status: .inProgress(userFraction: 0.1), inAppUpdatePriority: nil, countryTargeting: nil
            ))
        )

        let promote = GooglePlayReleaseChange.promote(
            fromTrack: "internal", versionCodes: ["43"], status: .draft, name: nil, releaseNotes: nil, inAppUpdatePriority: 2
        )
        XCTAssertEqual(
            GooglePlayAccountConnection.coreChange(promote),
            .promote(fromTrack: "internal", versionCodes: ["43"], status: .draft, name: nil, releaseNotes: nil, inAppUpdatePriority: 2, countryTargeting: nil)
        )
        XCTAssertTrue(promote.addsRelease)
        XCTAssertTrue(create.addsRelease)
        XCTAssertFalse(GooglePlayReleaseChange.halt(versionCodes: ["1"]).addsRelease)
    }

    func testCommitOptionsMapTheReviewBehaviour() {
        XCTAssertEqual(GooglePlayAccountConnection.coreOptions(.default),
                       CommitOptions(sendForReview: true, changesInReviewBehavior: .errorIfInReview))
        XCTAssertEqual(GooglePlayAccountConnection.coreOptions(GooglePlayCommitOptions(sendForReview: false, reviewInProgress: .cancelAndResubmit)),
                       CommitOptions(sendForReview: false, changesInReviewBehavior: .cancelInReviewAndSubmit))
    }

    // MARK: - Offline guard

    func testWritesAndBundlesFailFastOffline() async {
        let connection = GooglePlayAccountConnection(
            credentials: GooglePlayCredentials(serviceAccountJSON: GooglePlayTestFixtures.serviceAccountJSON()),
            connectivity: MockConnectivityProviding(online: false)
        )
        do {
            _ = try await connection.applyReleaseChange(packageName: "com.example.app", track: "production", change: .halt(versionCodes: ["1"]), options: .default)
            XCTFail("Expected OfflineError")
        } catch OfflineError.noConnection {
        } catch {
            XCTFail("Expected OfflineError.noConnection, got \(error)")
        }
        do {
            _ = try await connection.fetchBundles(packageName: "com.example.app")
            XCTFail("Expected OfflineError")
        } catch OfflineError.noConnection {
        } catch {
            XCTFail("Expected OfflineError.noConnection, got \(error)")
        }
    }

    // MARK: - Error copy

    private func releaseMessage(_ error: Error) -> String {
        GooglePlayErrorTranslator.friendlyMessage(for: error, operation: .releaseChange)
    }

    func testValidationFailureShowsGooglesMessage() {
        let error = StackError.Http(status: 400, message: "APK specifies a version code that has already been used.")

        XCTAssertEqual(
            releaseMessage(error),
            String(localized: "Google Play rejected this change. Nothing was published.") + "\nAPK specifies a version code that has already been used."
        )
        XCTAssertEqual(GooglePlayErrorTranslator.googleMessage(for: error), "APK specifies a version code that has already been used.")
    }

    func testMustNotBeSentForReviewGetsTheToggleHint() {
        let error = StackError.Http(status: 400, message: "Changes cannot be sent for review automatically. Please set the query parameter changesNotSentForReview to true.")

        XCTAssertEqual(releaseMessage(error), String(localized: "Google Play requires these changes to be saved without sending them for review. Turn off “Send changes for review” and try again."))
    }

    func testCommitWhileInReviewGetsTheReviewBehaviourHint() {
        let error = StackError.Http(status: 400, message: "Changes are already in review for this app.")

        XCTAssertEqual(releaseMessage(error), String(localized: "Another change to this app is in review. Choose “Cancel review and resubmit” under “If a review is in progress”, or try again when the review ends."))
    }

    func testReleaseThatNoLongerExists() {
        XCTAssertEqual(
            releaseMessage(StackError.ReleaseNotFound(message: "gone")),
            String(localized: "This release changed on Google Play since it was loaded. Refresh and try again.")
        )
        XCTAssertNil(GooglePlayErrorTranslator.googleMessage(for: StackError.ReleaseNotFound(message: "gone")))
    }

    func testServerErrorsAreNotGoogleValidationMessages() {
        XCTAssertNil(GooglePlayErrorTranslator.googleMessage(for: StackError.Http(status: 503, message: "Backend error")))
        XCTAssertEqual(releaseMessage(StackError.Http(status: 503, message: "Backend error")),
                       String(localized: "Google Play is temporarily unavailable. Try again in a few minutes."))
    }

    // MARK: - Flag

    private func flags(_ stored: Bool? = nil) -> FeatureFlags {
        let defaults = UserDefaults(suiteName: "GooglePlayReleaseWriteSeamsTests.\(UUID().uuidString)")!
        if let stored { defaults.set(stored, forKey: FeatureFlag.googlePlayReleaseWrites.rawValue) }
        return FeatureFlags(defaults: defaults)
    }

    func testWritesFlagIsOffByDefault() {
        XCTAssertFalse(FeatureFlag.googlePlayReleaseWrites.defaultValue)
        XCTAssertFalse(flags().isEnabled(.googlePlayReleaseWrites))
    }

    func testSessionDefaultTurnsTheFlagOnWithoutPersistingAndAStoredValueWins() {
        FeatureFlags.sessionDefaults[.googlePlayReleaseWrites] = true

        XCTAssertTrue(flags().isEnabled(.googlePlayReleaseWrites))
        XCTAssertFalse(flags(false).isEnabled(.googlePlayReleaseWrites))
    }

    // MARK: - Access

    private func account(version: [AccountPermission], appsBundles: [String]? = nil) -> AccountModel {
        AccountModel(
            name: "Imported",
            providerType: .googlePlay,
            rules: AccountRules(apps: AccountPermission.allCases, version: version, review: AccountPermission.allCases),
            origin: .imported,
            appsBundles: appsBundles
        )
    }

    func testWritesAreDeniedWithTheFlagOff() {
        let owner = AccountModel(name: "Play", providerType: .googlePlay)

        XCTAssertNotNil(GooglePlayReleaseWriteAccess.denialMessage(.edit, account: owner, app: app, featureFlags: flags(false)))
        XCTAssertNotNil(GooglePlayReleaseWriteAccess.denialMessage(.add, account: owner, app: app, featureFlags: flags(false)))
        XCTAssertTrue(GooglePlayReleaseWriteAccess.isAllowed(.add, account: owner, app: app, featureFlags: flags(true)))
    }

    func testEditNeedsTheVersionEditRuleAndAddTheVersionAddRule() {
        let viewOnly = account(version: [.view])
        XCTAssertFalse(GooglePlayReleaseWriteAccess.isAllowed(.edit, account: viewOnly, app: app, featureFlags: flags(true)))
        XCTAssertFalse(GooglePlayReleaseWriteAccess.isAllowed(.add, account: viewOnly, app: app, featureFlags: flags(true)))

        let editor = account(version: [.view, .edit])
        XCTAssertTrue(GooglePlayReleaseWriteAccess.isAllowed(.edit, account: editor, app: app, featureFlags: flags(true)))
        XCTAssertFalse(GooglePlayReleaseWriteAccess.isAllowed(.add, account: editor, app: app, featureFlags: flags(true)))

        XCTAssertEqual(GooglePlayReleaseWriteAccess.Kind(.promote(fromTrack: "internal", versionCodes: ["1"], status: .draft, name: nil, releaseNotes: nil, inAppUpdatePriority: nil)), .add)
    }

    func testWritesAreDeniedOutsideTheAccountsAppScope() {
        let scoped = account(version: AccountPermission.allCases, appsBundles: ["com.other.app"])

        XCTAssertEqual(
            GooglePlayReleaseWriteAccess.denialMessage(.edit, account: scoped, app: app, featureFlags: flags(true)),
            String(localized: "This app isn't included in the apps shared with this account.")
        )
    }
}
