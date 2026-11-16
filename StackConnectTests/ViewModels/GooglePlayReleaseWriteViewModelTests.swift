import XCTest
import StackCoreRust
@testable import StackConnect

/// The Google Play release write flow (plan T4, section 4): denied without the
/// `version` edit / add rule or with the flag off, nothing is sent before the
/// user confirms, a failed commit leaves the caches untouched and a successful
/// one updates the tracks cache and the summaries.
@MainActor
final class GooglePlayReleaseWriteViewModelTests: XCTestCase {

    private var storage: MockPersistentStorable!
    private var keychain: MockKeyStorable!
    private var connection: MockGooglePlayAccountConnection!
    private var defaults: UserDefaults!

    private let owner = AccountModel(name: "Play Team", providerType: .googlePlay)
    private let app = GooglePlayAppItem(id: "com.example.app", packageName: "com.example.app", title: "Example", isManuallyAdded: false)

    private let rolling = GooglePlayReleaseModel(
        name: "4.2.0 (4210)", status: .inProgress, versionCodes: ["4210"], userFraction: 0.2,
        releaseNotes: [GooglePlayLocalizedTextModel(language: "en-US", text: "Fixes")], inAppUpdatePriority: 2
    )
    private let published = GooglePlayReleaseModel(
        name: "4.1.2", status: .completed, versionCodes: ["4122"], userFraction: nil, releaseNotes: [], inAppUpdatePriority: nil
    )

    override func setUp() async throws {
        try await super.setUp()
        storage = MockPersistentStorable()
        keychain = MockKeyStorable()
        connection = MockGooglePlayAccountConnection()
        defaults = UserDefaults(suiteName: "GooglePlayReleaseWriteViewModelTests.\(UUID().uuidString)")
        defaults.set(true, forKey: FeatureFlag.googlePlayReleaseWrites.rawValue)
    }

    override func tearDown() async throws {
        storage = nil
        keychain = nil
        connection = nil
        defaults = nil
        try await super.tearDown()
    }

    // MARK: - Helpers

    private func makeSUT(account: AccountModel? = nil, credentials: Bool = true) -> GooglePlayReleaseWriteViewModel {
        let account = account ?? owner
        if credentials {
            keychain.setObject(
                GooglePlayCredentials(serviceAccountJSON: GooglePlayTestFixtures.serviceAccountJSON()),
                forKey: "credentials.\(account.id)"
            )
        }
        let writer = GooglePlayReleaseWriter(
            account: account,
            app: app,
            featureFlags: FeatureFlags(defaults: defaults),
            keychain: keychain,
            storage: storage,
            connectionFactory: connection.releaseWriteFactory
        )
        return GooglePlayReleaseWriteViewModel(writer: writer)
    }

    private func imported(version: [AccountPermission]) -> AccountModel {
        AccountModel(
            name: "Imported",
            providerType: .googlePlay,
            rules: AccountRules(apps: AccountPermission.allCases, version: version, review: AccountPermission.allCases),
            origin: .imported
        )
    }

    private func seedCaches(account: AccountModel? = nil) async throws {
        let account = account ?? owner
        let tracks = GooglePlayTracksCache(accountId: account.id, packageName: app.packageName, tracks: [
            GooglePlayTrackModel(track: "production", releases: [rolling, published]),
            GooglePlayTrackModel(track: "internal", releases: [])
        ])
        try await storage.save(tracks, id: tracks.cacheKey)
        let summaries = GooglePlayReleaseSummariesCache(accountId: account.id, packageName: app.packageName, summaries: [
            GooglePlayReleaseSummaryModel(track: "production", name: "4.2.0", lifecycleState: .inReview, versionCodes: ["4210"]),
            GooglePlayReleaseSummaryModel(track: "internal", name: "4.3.0", lifecycleState: .draft, versionCodes: ["4305"])
        ], fetchedAt: nil)
        try await storage.save(summaries, id: summaries.cacheKey)
    }

    private func cachedTracks(account: AccountModel? = nil) async throws -> [GooglePlayTrackModel]? {
        let account = account ?? owner
        return try await storage.fetch(GooglePlayTracksCache.self, id: GooglePlayTracksCache.cacheKey(accountId: account.id, packageName: app.packageName))?.tracks
    }

    private func cachedSummaries() async throws -> [GooglePlayReleaseSummaryModel]? {
        try await storage.fetch(GooglePlayReleaseSummariesCache.self, id: GooglePlayReleaseSummariesCache.cacheKey(accountId: owner.id, packageName: app.packageName))?.summaries
    }

    private func haltWrite() -> GooglePlayPendingWrite {
        GooglePlayPendingWrite(track: "production", change: .halt(versionCodes: ["4210"]), releaseTitle: "4.2.0")
    }

    // MARK: - Confirmation

    func testStartingAnActionOnlyAsksForConfirmation() async {
        let sut = makeSUT()

        sut.start(.halt, release: rolling, track: "production")

        XCTAssertEqual(sut.uiState.pendingWrite?.change, .halt(versionCodes: ["4210"]))
        XCTAssertTrue(sut.uiState.pendingWrite?.message.contains(GooglePlayPendingWrite.editWarning) ?? false, "R4: the confirmation states other edits are cancelled")
        XCTAssertTrue(connection.releaseChanges.isEmpty)
        XCTAssertTrue(connection.credentials.isEmpty)

        sut.cancelPendingWrite()
        XCTAssertNil(sut.uiState.pendingWrite)
        XCTAssertTrue(connection.releaseChanges.isEmpty)
    }

    func testReleaseToAllCompletesTheRelease() {
        let sut = makeSUT()

        sut.start(.releaseToAll, release: rolling, track: "production")

        XCTAssertEqual(sut.uiState.pendingWrite?.change, .complete(versionCodes: ["4210"]))
    }

    // MARK: - Staged rollout sheet

    func testIncreaseAndRollOutOpenTheRolloutSheetWithoutWriting() {
        let sut = makeSUT()

        sut.start(.increaseRollout, release: rolling, track: "production")

        XCTAssertEqual(sut.uiState.rolloutTarget, GooglePlayRolloutTarget(track: "production", release: rolling))
        XCTAssertTrue(sut.uiState.rolloutIncreasing)
        XCTAssertTrue(sut.uiState.isPresentingSheet)
        XCTAssertNil(sut.uiState.pendingWrite)
        XCTAssertTrue(connection.releaseChanges.isEmpty)
    }

    func testRollingOutADraftOnATrackWithoutStagedRolloutReleasesToAll() {
        let sut = makeSUT()
        let draft = GooglePlayReleaseModel(name: "4.3.0", status: .draft, versionCodes: ["4305"], userFraction: nil, releaseNotes: [], inAppUpdatePriority: nil)

        sut.start(.rollOut, release: draft, track: "internal")

        XCTAssertNil(sut.uiState.rolloutTarget)
        XCTAssertEqual(sut.uiState.pendingWrite?.change, .complete(versionCodes: ["4305"]))
    }

    func testRolloutFormStartsOnTheNextStepWhenIncreasing() {
        let target = GooglePlayRolloutTarget(track: "production", release: rolling)

        XCTAssertEqual(GooglePlayRolloutForm(target: target, increasing: true).percent, 50)
        XCTAssertEqual(GooglePlayRolloutForm(target: target).percent, 20)
        XCTAssertEqual(GooglePlayRolloutForm(target: target).method, .percentage)
    }

    func testRolloutFormChanges() {
        let target = GooglePlayRolloutTarget(track: "production", release: rolling)
        var form = GooglePlayRolloutForm(target: target)

        XCTAssertNil(form.change(for: target), "Saving the running fraction changes nothing")
        form.percent = 50
        XCTAssertEqual(form.change(for: target), .setRollout(versionCodes: ["4210"], userFraction: 0.5))
        form.method = .allUsers
        XCTAssertEqual(form.change(for: target), .complete(versionCodes: ["4210"]))
    }

    func testRolloutFormOnATrackWithoutStagedRolloutReleasesToAll() {
        let draft = GooglePlayReleaseModel(name: "4.3.0", status: .draft, versionCodes: ["4305"], userFraction: nil, releaseNotes: [], inAppUpdatePriority: nil)
        let target = GooglePlayRolloutTarget(track: "alpha", release: draft)

        let form = GooglePlayRolloutForm(target: target)

        XCTAssertEqual(form.method, .allUsers)
        XCTAssertEqual(form.change(for: target), .complete(versionCodes: ["4305"]))
    }

    // MARK: - Review checklist

    func testPublishingWritesUseTheChecklistAndHaltUsesAnAlert() {
        let sut = makeSUT()

        sut.start(.releaseToAll, release: rolling, track: "production")
        XCTAssertEqual(sut.uiState.checklistWrite?.change, .complete(versionCodes: ["4210"]))

        sut.start(.halt, release: rolling, track: "production")
        XCTAssertNil(sut.uiState.checklistWrite)
        XCTAssertNotNil(sut.uiState.pendingWrite)
    }

    func testChecklistFailureStaysInTheChecklistWithGooglesMessage() async throws {
        try await seedCaches()
        connection.applyReleaseChangeHandler = { _ in
            throw StackError.Http(status: 400, message: "Changes cannot be sent for review automatically. Please set the query parameter changesNotSentForReview to true.")
        }
        let sut = makeSUT()
        sut.start(.releaseToAll, release: rolling, track: "production")
        let write = try XCTUnwrap(sut.uiState.checklistWrite)
        sut.uiState.commitOptions.reviewInProgress = .cancelAndResubmit

        let ok = await sut.confirm(write)

        XCTAssertFalse(ok)
        XCTAssertEqual(connection.releaseChanges.first?.options, GooglePlayCommitOptions(sendForReview: true, reviewInProgress: .cancelAndResubmit))
        XCTAssertEqual(sut.uiState.checklistWrite, write, "The checklist stays open")
        XCTAssertEqual(sut.uiState.checklistError, String(localized: "Google Play requires these changes to be saved without sending them for review. Turn off “Send changes for review” and try again."))
        XCTAssertNil(sut.uiState.errorMessage)
        let tracks = try await cachedTracks()
        XCTAssertEqual(tracks?.first?.releases, [rolling, published])

        sut.uiState.commitOptions.sendForReview = false
        connection.applyReleaseChangeHandler = { request in GooglePlayTrackModel(track: request.track, releases: []) }
        let retried = await sut.confirm(write)
        XCTAssertTrue(retried)
        XCTAssertEqual(connection.releaseChanges.last?.options.sendForReview, false)
        XCTAssertNil(sut.uiState.checklistWrite)
        XCTAssertNil(sut.uiState.checklistError)
    }

    func testChecklistItems() async throws {
        try await seedCaches()
        let listings = GooglePlayStoreListingsCache(accountId: owner.id, packageName: app.packageName, listings: [
            GooglePlayStoreListingModel(language: "en-US", title: "Example", shortDescription: "", fullDescription: "", video: nil),
            GooglePlayStoreListingModel(language: "pt-BR", title: "Exemplo", shortDescription: "", fullDescription: "", video: nil)
        ])
        try await storage.save(listings, id: listings.cacheKey)
        let sut = makeSUT()
        await sut.loadContext()
        let promote = GooglePlayPendingWrite(
            track: "production",
            change: .promote(fromTrack: "internal", versionCodes: ["4305"], status: .inProgress(userFraction: 0.1), name: "4.3.0", releaseNotes: nil, inAppUpdatePriority: nil),
            releaseTitle: "4.3.0",
            release: GooglePlayReleaseModel(name: "4.3.0", status: .draft, versionCodes: ["4305"], userFraction: nil,
                                            releaseNotes: [GooglePlayLocalizedTextModel(language: "en-US", text: "New")], inAppUpdatePriority: nil)
        )

        let checklist = sut.checklist(for: promote)

        XCTAssertEqual(checklist.items.map(\.id), ["bundle", "name", "notes", "rollout", "versionCode"])
        let notes = try XCTUnwrap(checklist.items.first { $0.id == "notes" })
        XCTAssertEqual(notes.state, .warning, "Missing in Portuguese")
        XCTAssertEqual(notes.value, String(localized: "\(1) of \(2)"))
        let versionCode = try XCTUnwrap(checklist.items.first { $0.id == "versionCode" })
        XCTAssertEqual(versionCode.state, .satisfied)
        XCTAssertEqual(versionCode.value, "4305 > 4210")
        XCTAssertTrue(checklist.hasWarnings)
    }

    func testChecklistFlagsAVersionCodeNotAboveTheLiveOne() {
        let track = GooglePlayTrackModel(track: "production", releases: [rolling, published])
        let create = GooglePlayPendingWrite(
            track: "production",
            change: .create(GooglePlayNewRelease(versionCodes: ["4200"], name: "4.2.0", releaseNotes: [], status: .completed, inAppUpdatePriority: nil)),
            releaseTitle: "4.2.0"
        )

        let checklist = GooglePlayReviewChecklist.make(write: create, listingLanguages: [], liveVersionCode: GooglePlayReviewChecklist.liveVersionCode(on: track))

        XCTAssertEqual(checklist.items.first { $0.id == "versionCode" }?.state, .warning)
    }

    // MARK: - New release / promote

    func testPromoteAndNewReleaseOpenTheSheetOnlyWithTheAddRule() {
        let sut = makeSUT()
        sut.start(.promote, release: published, track: "internal")
        XCTAssertEqual(sut.uiState.newRelease?.source, .promote(fromTrack: "internal", release: published))
        XCTAssertTrue(sut.uiState.isPresentingSheet)

        let editor = makeSUT(account: imported(version: [.view, .edit]))
        editor.start(.promote, release: published, track: "internal")
        editor.openNewRelease(track: "production")
        XCTAssertNil(editor.uiState.newRelease)
        XCTAssertTrue(connection.releaseChanges.isEmpty)
    }

    func testBundlesNeedTheAddRule() async {
        connection.fetchBundlesHandler = { _ in [GooglePlayBundleModel(versionCode: "1", sha256: nil), GooglePlayBundleModel(versionCode: "3", sha256: nil)] }
        let sut = makeSUT()
        let bundles = try? await sut.fetchBundles()
        XCTAssertEqual(bundles?.map(\.versionCode), ["3", "1"], "Newest first")

        let editor = makeSUT(account: imported(version: [.view, .edit]))
        do {
            _ = try await editor.fetchBundles()
            XCTFail("Expected a denial")
        } catch {}
        XCTAssertEqual(connection.bundlesRequests.count, 1)
    }

    // MARK: - Access

    func testWritesAreDeniedWithTheFlagOff() async {
        defaults.set(false, forKey: FeatureFlag.googlePlayReleaseWrites.rawValue)
        let sut = makeSUT()

        XCTAssertFalse(sut.canPerform(.edit))
        sut.start(.halt, release: rolling, track: "production")
        XCTAssertNil(sut.uiState.pendingWrite)

        let ok = await sut.confirm(haltWrite())
        XCTAssertFalse(ok)
        XCTAssertTrue(connection.releaseChanges.isEmpty)
    }

    func testChangingAReleaseNeedsTheVersionEditRule() async {
        let sut = makeSUT(account: imported(version: [.view]))

        XCTAssertFalse(sut.canPerform(.edit))
        sut.request(haltWrite())
        XCTAssertNil(sut.uiState.pendingWrite)
        let ok = await sut.confirm(haltWrite())
        XCTAssertFalse(ok)
        XCTAssertTrue(connection.releaseChanges.isEmpty)
    }

    func testCreatingAReleaseNeedsTheVersionAddRule() async {
        let sut = makeSUT(account: imported(version: [.view, .edit]))
        let create = GooglePlayPendingWrite(
            track: "internal",
            change: .create(GooglePlayNewRelease(versionCodes: ["4400"], name: nil, releaseNotes: [], status: .draft, inAppUpdatePriority: nil)),
            releaseTitle: "4400"
        )

        XCTAssertTrue(sut.canPerform(.edit))
        XCTAssertFalse(sut.canPerform(.add))
        let ok = await sut.confirm(create)
        XCTAssertFalse(ok)
        XCTAssertTrue(connection.releaseChanges.isEmpty)
    }

    func testTheWriterRefusesADeniedChangeEvenWhenCalledDirectly() async {
        let writer = GooglePlayReleaseWriter(
            account: imported(version: [.view]), app: app, featureFlags: FeatureFlags(defaults: defaults),
            keychain: keychain, storage: storage, connectionFactory: connection.releaseWriteFactory
        )

        do {
            try await writer.apply(.halt(versionCodes: ["4210"]), track: "production", options: .default)
            XCTFail("Expected a denial")
        } catch let error as GooglePlayReleaseWriteError {
            XCTAssertEqual(error, .denied(String(localized: "You don't have permission to change this app's releases.")))
        } catch {
            XCTFail("Unexpected \(error)")
        }
        XCTAssertTrue(connection.releaseChanges.isEmpty)
    }

    // MARK: - Commit

    func testSuccessfulWriteUpdatesTheTracksCacheAndTheSummaries() async throws {
        try await seedCaches()
        var halted = rolling
        halted.status = .halted
        connection.applyReleaseChangeHandler = { request in
            GooglePlayTrackModel(track: request.track, releases: [halted])
        }
        connection.fetchReleaseSummariesHandler = { _, track in
            [GooglePlayReleaseSummaryModel(track: track, name: "4.2.0", lifecycleState: .notSentForReview, versionCodes: ["4210"])]
        }
        let sut = makeSUT()
        let write = haltWrite()
        sut.request(write)

        let ok = await sut.confirm(write)

        XCTAssertTrue(ok)
        XCTAssertEqual(connection.releaseChanges.map(\.change), [.halt(versionCodes: ["4210"])])
        XCTAssertEqual(connection.releaseChanges.first?.options, .default)
        XCTAssertNil(sut.uiState.pendingWrite)
        XCTAssertEqual(sut.uiState.toastMessage?.text, String(localized: "Rollout halted"))
        XCTAssertEqual(sut.uiState.revision, 1)

        let tracks = try await cachedTracks()
        XCTAssertEqual(tracks?.first { $0.track == "production" }?.releases, [halted])
        XCTAssertEqual(tracks?.map(\.track), ["production", "internal"], "Other tracks are kept")
        let summaries = try await cachedSummaries()
        XCTAssertEqual(summaries?.first { $0.track == "production" }?.lifecycleState, .notSentForReview)
        XCTAssertEqual(summaries?.first { $0.track == "internal" }?.lifecycleState, .draft, "Other tracks' summaries are kept")
        XCTAssertEqual(connection.releaseSummaryRequests.map(\.track), ["production"])
    }

    func testFailedCommitLeavesTheCachesUntouched() async throws {
        try await seedCaches()
        connection.applyReleaseChangeHandler = { _ in
            throw StackError.Http(status: 400, message: "Version code 4210 is not valid.")
        }
        let sut = makeSUT()

        let ok = await sut.confirm(haltWrite())

        XCTAssertFalse(ok)
        XCTAssertEqual(
            sut.uiState.errorMessage,
            String(localized: "Google Play rejected this change. Nothing was published.") + "\nVersion code 4210 is not valid."
        )
        XCTAssertNil(sut.uiState.toastMessage)
        XCTAssertEqual(sut.uiState.revision, 0)
        let tracks = try await cachedTracks()
        let summaries = try await cachedSummaries()
        XCTAssertEqual(tracks?.first?.releases, [rolling, published])
        XCTAssertEqual(summaries?.first?.lifecycleState, .inReview)
        XCTAssertTrue(connection.releaseSummaryRequests.isEmpty)
    }

    func testAFailedSummariesRefreshStillKeepsTheCommittedTrack() async throws {
        try await seedCaches()
        connection.applyReleaseChangeHandler = { request in GooglePlayTrackModel(track: request.track, releases: []) }
        connection.fetchReleaseSummariesHandler = { _, _ in throw OfflineError.noConnection }
        let sut = makeSUT()

        let ok = await sut.confirm(haltWrite())

        XCTAssertTrue(ok)
        let tracks = try await cachedTracks()
        let summaries = try await cachedSummaries()
        XCTAssertEqual(tracks?.first?.releases, [])
        XCTAssertEqual(summaries?.first?.lifecycleState, .inReview)
    }

    func testMissingCredentialsAreReported() async {
        let sut = makeSUT(credentials: false)

        let ok = await sut.confirm(haltWrite())

        XCTAssertFalse(ok)
        XCTAssertEqual(sut.uiState.errorMessage, String(localized: "No credentials found for this account."))
    }

    // MARK: - Release detail

    func testReleaseDetailOffersActionsAndEditingOnlyWhenAllowed() async throws {
        try await seedCaches()
        let detail = GooglePlayReleaseDetailViewModel(
            app: app, account: owner, track: "production", release: rolling,
            storage: storage, featureFlags: FeatureFlags(defaults: defaults)
        )
        await detail.load()

        XCTAssertEqual(detail.uiState.lifecycleState, .inReview)
        XCTAssertEqual(detail.uiState.actions, [.increaseRollout, .halt, .releaseToAll])
        XCTAssertTrue(detail.uiState.canEditMetadata)

        defaults.set(false, forKey: FeatureFlag.googlePlayReleaseWrites.rawValue)
        let readOnly = GooglePlayReleaseDetailViewModel(
            app: app, account: owner, track: "production", release: rolling,
            storage: storage, featureFlags: FeatureFlags(defaults: defaults)
        )
        await readOnly.load()
        XCTAssertTrue(readOnly.uiState.actions.isEmpty)
        XCTAssertFalse(readOnly.uiState.canEditMetadata)
    }

    func testReleaseDetailBuildsAMetadataChangeWithOnlyTheEditedFields() {
        let detail = GooglePlayReleaseDetailViewModel(
            app: app, account: owner, track: "production", release: rolling,
            storage: storage, featureFlags: FeatureFlags(defaults: defaults)
        )
        XCTAssertNil(detail.metadataWrite())

        detail.uiState.draft?.notes["en-US"] = "Faster sync"
        let write = detail.metadataWrite()

        XCTAssertEqual(write?.change, .updateMetadata(versionCodes: ["4210"], update: GooglePlayReleaseMetadataUpdate(
            name: nil,
            releaseNotes: [GooglePlayLocalizedTextModel(language: "en-US", text: "Faster sync")],
            inAppUpdatePriority: nil
        )))
        detail.discardChanges()
        XCTAssertFalse(detail.uiState.hasChanges)
    }
}
