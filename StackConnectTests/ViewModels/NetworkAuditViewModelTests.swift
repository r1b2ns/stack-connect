import XCTest
@testable import StackConnect

@MainActor
final class NetworkAuditViewModelTests: XCTestCase {

    private let now = NetworkAuditFixtures.now
    private let token = NetworkAuditFixtures.ascJWT(expiresAt: NetworkAuditFixtures.now.addingTimeInterval(600))

    private func event(_ url: String, hoursAgo: Double = 0, status: Int? = 200, authorization: String? = nil) -> NetworkAuditEvent {
        NetworkAuditFixtures.event(NetworkAuditFixtures.exchange(
            url: url,
            authorization: authorization,
            status: status,
            startedAt: now.addingTimeInterval(-hoursAgo * 3_600)
        ))
    }

    private func localEvent(hoursAgo: Double) -> NetworkAuditEvent {
        let recorder = NetworkAuditRecorder(store: MockNetworkAuditStore(), settings: MockNetworkAuditSettings(),
                                            vault: NetworkAuditSecretVault(keychain: MockKeyStorable()),
                                            now: { [now] in now.addingTimeInterval(-hoursAgo * 3_600) })
        return recorder.makeExportEvent(NetworkAuditExportRecord(formatName: "cURL", subject: "GET /v1/apps", action: .copied, includesRealToken: false, byteCount: 1))
    }

    // MARK: - List

    private func makeList(_ events: [NetworkAuditEvent]) async -> NetworkAuditViewModel {
        let deps = NetworkAuditFixtures.dependencies(store: MockNetworkAuditStore(events: events))
        let sut = NetworkAuditViewModel(dependencies: deps, calendar: NetworkAuditFixtures.utcCalendar)
        await sut.load()
        return sut
    }

    func testLoadGroupsByDayAndSummarizesToday() async {
        let sut = await makeList([
            event("https://api.appstoreconnect.apple.com/v1/apps", hoursAgo: 1),
            event("https://app-measurement.com/a", hoursAgo: 2),
            event("https://api.appstoreconnect.apple.com/v1/users/1", hoursAgo: 3, status: 409),
            event("https://firebase.googleapis.com/v1beta1/projects", hoursAgo: 26),
            localEvent(hoursAgo: 0.5)
        ])

        XCTAssertFalse(sut.uiState.isLoading)
        XCTAssertEqual(sut.uiState.groups.map(\.title), [String(localized: "Today"), String(localized: "Yesterday")])
        XCTAssertEqual(sut.uiState.groups.first?.events.count, 4)
        XCTAssertEqual(sut.uiState.today.requestCount, 3)
        XCTAssertEqual(sut.uiState.today.destinationCount, 2)
        XCTAssertEqual(sut.uiState.totalCount, 5)
        XCTAssertEqual(sut.uiState.retentionDays, 15)
    }

    func testFiltersAndSearch() async {
        let sut = await makeList([
            event("https://api.appstoreconnect.apple.com/v1/apps"),
            event("https://app-measurement.com/a"),
            event("https://api.appstoreconnect.apple.com/v1/users/1", status: 409),
            event("https://androidpublisher.googleapis.com/androidpublisher/v3/applications"),
            localEvent(hoursAgo: 0)
        ])

        sut.selectFilter(.apple)
        XCTAssertEqual(sut.uiState.visibleCount, 2)
        sut.selectFilter(.google)
        XCTAssertEqual(sut.uiState.visibleCount, 1)
        sut.selectFilter(.telemetry)
        XCTAssertEqual(sut.uiState.visibleCount, 1)
        sut.selectFilter(.local)
        XCTAssertEqual(sut.uiState.visibleCount, 1)
        sut.selectFilter(.errors)
        XCTAssertEqual(sut.filteredSummaries.map(\.statusCode), [409])

        sut.selectFilter(.all)
        sut.updateSearch("users")
        XCTAssertEqual(sut.uiState.visibleCount, 1)
        sut.updateSearch("nothing-matches")
        XCTAssertTrue(sut.uiState.groups.isEmpty)
    }

    func testDestinationsAggregatePerHost() async {
        let sut = await makeList([
            event("https://api.appstoreconnect.apple.com/v1/apps"),
            event("https://api.appstoreconnect.apple.com/v1/builds"),
            event("https://app-measurement.com/a"),
            localEvent(hoursAgo: 0)
        ])

        XCTAssertEqual(sut.uiState.destinations.map(\.host), ["api.appstoreconnect.apple.com", "app-measurement.com"])
        XCTAssertEqual(sut.uiState.destinations.first?.requestCount, 2)
        XCTAssertEqual(sut.uiState.destinations.first?.bytesReceived, 70)
        XCTAssertEqual(sut.uiState.destinations.last?.category, .telemetry)
    }

    func testRetentionLimitsTheList() async {
        let settings = MockNetworkAuditSettings()
        settings.retention = .sevenDays
        let deps = NetworkAuditFixtures.dependencies(
            store: MockNetworkAuditStore(events: [event("https://a.example.com/", hoursAgo: 24 * 10), event("https://b.example.com/")]),
            settings: settings
        )
        let sut = NetworkAuditViewModel(dependencies: deps, calendar: NetworkAuditFixtures.utcCalendar)

        await sut.load()

        XCTAssertEqual(sut.uiState.totalCount, 1)
        XCTAssertEqual(sut.uiState.retentionDays, 7)
    }

    func testCopyHostIsNotSensitiveAndShowsToast() async {
        let pasteboard = MockNetworkAuditPasteboard()
        let sut = NetworkAuditViewModel(dependencies: NetworkAuditFixtures.dependencies(pasteboard: pasteboard))

        sut.copyHost("app-measurement.com")

        XCTAssertEqual(pasteboard.copies.first?.text, "app-measurement.com")
        XCTAssertEqual(pasteboard.copies.first?.sensitive, false)
        XCTAssertEqual(sut.uiState.toast?.text, String(localized: "Copied: \("app-measurement.com")"))
    }

    // MARK: - Detail

    func testDetailRevealsSecretsOnlyAfterAuthentication() async throws {
        let vault = NetworkAuditSecretVault(keychain: MockKeyStorable())
        let stored = NetworkAuditFixtures.event(NetworkAuditFixtures.exchange(authorization: "Bearer \(token)"), vault: vault)
        let authenticator = MockNetworkAuditAuthenticator(result: false)
        let pasteboard = MockNetworkAuditPasteboard()
        let sut = NetworkAuditDetailViewModel(
            summary: stored.summary,
            dependencies: NetworkAuditFixtures.dependencies(store: MockNetworkAuditStore(events: [stored]), vault: vault,
                                                            authenticator: authenticator, pasteboard: pasteboard)
        )
        await sut.load()
        let header = try XCTUnwrap(sut.uiState.headers.first { $0.name == "Authorization" })
        XCTAssertTrue(header.isSecret)
        XCTAssertFalse(header.displayValue.contains(token))

        // Declined: stays masked, and copying copies the masked value.
        await sut.toggleSecrets()
        XCTAssertFalse(sut.uiState.isRevealed)
        sut.copyHeader(header)
        XCTAssertEqual(pasteboard.copies.last?.text, "Authorization: Bearer [MASKED]")
        XCTAssertEqual(pasteboard.copies.last?.sensitive, false)

        // Confirmed: revealed, and copying is local-only and expiring.
        authenticator.result = true
        await sut.toggleSecrets()
        XCTAssertTrue(sut.uiState.isRevealed)
        let revealed = try XCTUnwrap(sut.uiState.headers.first { $0.name == "Authorization" })
        XCTAssertEqual(revealed.displayValue, "Bearer \(token)")
        sut.copyHeader(revealed)
        XCTAssertEqual(pasteboard.copies.last?.text, "Authorization: Bearer \(token)")
        XCTAssertEqual(pasteboard.copies.last?.sensitive, true)

        // Copy All always masks.
        sut.copyAllHeaders()
        XCTAssertFalse(pasteboard.copies.last?.text.contains(token) ?? true)

        await sut.toggleSecrets()
        XCTAssertFalse(sut.uiState.isRevealed)
        XCTAssertEqual(authenticator.reasons.count, 2)
    }

    func testDetailRowsAndTabs() async {
        let stored = event("https://api.appstoreconnect.apple.com/v1/apps")
        let sut = NetworkAuditDetailViewModel(summary: stored.summary,
                                              dependencies: NetworkAuditFixtures.dependencies(store: MockNetworkAuditStore(events: [stored])))

        await sut.load()

        XCTAssertEqual(sut.uiState.whyRows.count, 3)
        XCTAssertTrue(sut.uiState.summaryRows.contains { $0.label == String(localized: "Duration") && $0.value == "412 ms" })
        XCTAssertTrue(sut.uiState.summaryRows.contains { $0.label == String(localized: "Connection") && $0.value == "TLS 1.3 · HTTP/2" })
        XCTAssertEqual(sut.uiState.headers.map(\.name), ["Accept"])

        sut.selectTab(.response)
        XCTAssertEqual(sut.uiState.headers.map(\.name), ["Content-Type"])
        XCTAssertNotNil(sut.uiState.body.text)
    }

    func testDetailOfADeletedEvent() async {
        let sut = NetworkAuditDetailViewModel(summary: event("https://a.example.com/").summary,
                                              dependencies: NetworkAuditFixtures.dependencies())

        await sut.load()

        XCTAssertFalse(sut.uiState.isLoading)
        XCTAssertNil(sut.uiState.event)
    }

    // MARK: - Retention

    func testLongerRetentionAppliesAtOnce() async {
        let settings = MockNetworkAuditSettings()
        let sut = NetworkAuditRetentionViewModel(dependencies: NetworkAuditFixtures.dependencies(settings: settings))
        await sut.load()

        await sut.select(.thirtyDays)

        XCTAssertEqual(settings.retention, .thirtyDays)
        XCTAssertNil(sut.uiState.pendingReduction)
    }

    func testShorterRetentionAsksThenPurges() async {
        let store = MockNetworkAuditStore(events: [
            event("https://a.example.com/", hoursAgo: 24 * 10),
            event("https://b.example.com/", hoursAgo: 24 * 12),
            event("https://c.example.com/", hoursAgo: 1)
        ])
        let settings = MockNetworkAuditSettings()
        let sut = NetworkAuditRetentionViewModel(dependencies: NetworkAuditFixtures.dependencies(store: store, settings: settings))
        await sut.load()

        await sut.select(.sevenDays)

        XCTAssertEqual(sut.uiState.pendingReduction?.eventCount, 2)
        XCTAssertEqual(settings.retention, .fifteenDays, "nothing changes before the confirmation")

        await sut.confirmReduction()

        XCTAssertEqual(settings.retention, .sevenDays)
        XCTAssertNil(sut.uiState.pendingReduction)
        let remaining = await store.events
        XCTAssertEqual(remaining.count, 1)
        XCTAssertEqual(sut.uiState.stats.eventCount, 1)
    }

    func testCancelledReductionKeepsEverything() async {
        let store = MockNetworkAuditStore(events: [event("https://a.example.com/", hoursAgo: 24 * 10)])
        let settings = MockNetworkAuditSettings()
        let sut = NetworkAuditRetentionViewModel(dependencies: NetworkAuditFixtures.dependencies(store: store, settings: settings))
        await sut.load()

        await sut.select(.sevenDays)
        sut.cancelReduction()

        XCTAssertNil(sut.uiState.pendingReduction)
        XCTAssertEqual(settings.retention, .fifteenDays)
        let purges = await store.purgeCutoffs
        XCTAssertTrue(purges.isEmpty)
    }

    func testFullBodiesAndDeleteAll() async {
        let keychain = MockKeyStorable()
        let vault = NetworkAuditSecretVault(keychain: keychain)
        _ = vault.seal(["request.0": "x"])
        let store = MockNetworkAuditStore(events: [event("https://a.example.com/")])
        let settings = MockNetworkAuditSettings()
        let sut = NetworkAuditRetentionViewModel(dependencies: NetworkAuditFixtures.dependencies(store: store, settings: settings, vault: vault))
        await sut.load()

        sut.setRecordsFullBodies(false)
        await sut.deleteAll()

        XCTAssertFalse(settings.recordsFullBodies)
        XCTAssertEqual(sut.uiState.stats.eventCount, 0)
        XCTAssertNil(keychain.data(forKey: NetworkAuditSecretVault.keychainKey))
        XCTAssertNotNil(sut.uiState.toast)
    }

    // MARK: - Event export

    private func makeEventExport(
        expiresIn: TimeInterval,
        authenticates: Bool = true
    ) async -> (NetworkAuditEventExportViewModel, MockNetworkAuditPasteboard, MockNetworkAuditLocalRecorder, String) {
        let jwt = NetworkAuditFixtures.ascJWT(expiresAt: now.addingTimeInterval(expiresIn))
        let vault = NetworkAuditSecretVault(keychain: MockKeyStorable())
        let stored = NetworkAuditFixtures.event(NetworkAuditFixtures.exchange(authorization: "Bearer \(jwt)"), vault: vault)
        let pasteboard = MockNetworkAuditPasteboard()
        let recorder = MockNetworkAuditLocalRecorder()
        let sut = NetworkAuditEventExportViewModel(
            summary: stored.summary,
            dependencies: NetworkAuditFixtures.dependencies(
                store: MockNetworkAuditStore(events: [stored]),
                vault: vault,
                recorder: recorder,
                authenticator: MockNetworkAuditAuthenticator(result: authenticates),
                pasteboard: pasteboard
            )
        )
        await sut.load()
        return (sut, pasteboard, recorder, jwt)
    }

    func testCurlIsMaskedUntilTheTokenIsIncluded() async {
        let (sut, pasteboard, recorder, jwt) = await makeEventExport(expiresIn: 600)

        XCTAssertTrue(sut.uiState.showsTokenToggle)
        XCTAssertTrue(sut.uiState.canToggleToken)
        XCTAssertFalse(sut.uiState.preview.contains(jwt))

        sut.copy()
        XCTAssertFalse(pasteboard.copies.last?.text.contains(jwt) ?? true)
        XCTAssertEqual(pasteboard.copies.last?.sensitive, true)
        XCTAssertEqual(recorder.exports.last?.includesRealToken, false)
        XCTAssertEqual(recorder.exports.last?.action, .copied)

        await sut.setIncludeRealToken(true)
        XCTAssertTrue(sut.uiState.includesRealToken)
        // The preview only shows the first characters of the real token.
        XCTAssertFalse(sut.uiState.preview.contains(jwt))

        sut.copy()
        XCTAssertTrue(pasteboard.copies.last?.text.contains("Authorization: Bearer \(jwt)") ?? false)
        XCTAssertEqual(recorder.exports.last?.includesRealToken, true)
        XCTAssertEqual(recorder.exports.last?.formatName, "cURL")
    }

    func testOtherFormatsNeverCarryTheToken() async {
        let (sut, pasteboard, _, jwt) = await makeEventExport(expiresIn: 600)
        await sut.setIncludeRealToken(true)

        sut.selectFormat(.json)
        sut.copy()

        XCTAssertFalse(sut.uiState.includesRealToken)
        XCTAssertFalse(sut.uiState.showsTokenToggle)
        XCTAssertFalse(pasteboard.copies.last?.text.contains(jwt) ?? true)
    }

    func testExpiredTokenCantBeIncluded() async {
        let (sut, _, _, _) = await makeEventExport(expiresIn: -60)

        await sut.setIncludeRealToken(true)

        XCTAssertFalse(sut.uiState.includesRealToken)
        XCTAssertFalse(sut.uiState.canToggleToken)
        if case .expired = sut.uiState.tokenInclusion {} else {
            XCTFail("expected an expired token, got \(sut.uiState.tokenInclusion)")
        }
    }

    func testDeclinedFaceIDKeepsTheTokenMasked() async {
        let (sut, _, _, _) = await makeEventExport(expiresIn: 600, authenticates: false)

        await sut.setIncludeRealToken(true)

        XCTAssertFalse(sut.uiState.includesRealToken)
    }

    func testShareWritesAFileAndRecordsTheExport() async throws {
        let (sut, _, recorder, _) = await makeEventExport(expiresIn: 600)
        sut.selectFormat(.har)

        sut.share()

        let item = try XCTUnwrap(sut.uiState.shareItem)
        XCTAssertTrue(FileManager.default.fileExists(atPath: item.fileURL.path))
        XCTAssertEqual(item.fileURL.pathExtension, "har")
        XCTAssertEqual(recorder.exports.last?.action, .shared)

        sut.shareDidFinish()
        XCTAssertNil(sut.uiState.shareItem)
        XCTAssertFalse(FileManager.default.fileExists(atPath: item.fileURL.path))
    }

    // MARK: - Batch export

    func testBatchExportScopesAndShare() async throws {
        let events = [
            event("https://api.appstoreconnect.apple.com/v1/apps", hoursAgo: 1),
            event("https://app-measurement.com/a", hoursAgo: 2),
            event("https://firebase.googleapis.com/v1beta1/projects", hoursAgo: 30)
        ]
        let recorder = MockNetworkAuditLocalRecorder()
        let filtered = [events[0].summary]
        let sut = NetworkAuditExportViewModel(
            filteredSummaries: filtered,
            filterTitle: "Apple",
            dependencies: NetworkAuditFixtures.dependencies(store: MockNetworkAuditStore(events: events), recorder: recorder),
            calendar: NetworkAuditFixtures.utcCalendar
        )

        await sut.load()

        XCTAssertEqual(sut.uiState.counts[.currentFilter], 1)
        XCTAssertEqual(sut.uiState.counts[.today], 2)
        XCTAssertEqual(sut.uiState.counts[.entireLog], 3)
        XCTAssertTrue(sut.uiState.preview.hasPrefix("["))

        await sut.selectFormat(.csv)
        XCTAssertTrue(sut.uiState.preview.hasPrefix(NetworkAuditExporter.csvHeader))

        await sut.selectScope(.entireLog)
        await sut.export()

        let item = try XCTUnwrap(sut.uiState.shareItem)
        let content = try String(contentsOf: item.fileURL, encoding: .utf8)
        XCTAssertEqual(content.split(separator: "\n").count, 4)
        XCTAssertEqual(recorder.exports.last?.formatName, "CSV")
        XCTAssertEqual(recorder.exports.last?.includesRealToken, false)
        sut.shareDidFinish()
    }

    // MARK: - Settings entry

    func testSettingsShowsTheAuditRowOnlyWithTheFlag() {
        let suite = "NetworkAuditFlag.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let flags = FeatureFlags(defaults: defaults, remoteValues: StubRemoteFeatureValues())

        defaults.set(false, forKey: FeatureFlag.networkAudit.rawValue)
        let off = SettingsViewModel(storage: MockPersistentStorable(), keychain: MockKeyStorable(), analytics: MockAnalyticsTracker(), featureFlags: flags)
        XCTAssertFalse(off.uiState.showsNetworkAudit)

        defaults.set(true, forKey: FeatureFlag.networkAudit.rawValue)
        let on = SettingsViewModel(storage: MockPersistentStorable(), keychain: MockKeyStorable(), analytics: MockAnalyticsTracker(), featureFlags: flags)
        XCTAssertTrue(on.uiState.showsNetworkAudit)
    }

    func testNetworkAuditFlagDefaults() {
        #if DEBUG
        XCTAssertTrue(FeatureFlag.networkAudit.defaultValue)
        #else
        XCTAssertFalse(FeatureFlag.networkAudit.defaultValue)
        #endif
        XCTAssertNil(FeatureFlag.networkAudit.remoteConfigKey)
    }

    // MARK: - iPad split view

    func testAuditTakesTheWholeWidthOfTheSplitView() {
        let split = RootSplitCoordinator(analytics: MockAnalyticsTracker())
        split.select(.settings, origin: .sidebar)

        split.showInDetail(.networkAudit)
        XCTAssertEqual(split.columnVisibility, .detailOnly)

        split.showInDetail(.license)
        XCTAssertEqual(split.columnVisibility, .automatic)

        split.showInDetail(.networkAudit)
        split.select(.dashboard, origin: .sidebar)
        XCTAssertEqual(split.columnVisibility, .automatic)
    }
}
