import XCTest
import StackProtocols
@testable import StackConnect

/// The Home side of the automatic Apple ID sign-in: no banner while it runs,
/// "Confirm your Apple account" while its code waits, the "reconnecting"
/// tip and the "reconnected" toast.
@MainActor
final class HomeViewModelAutoReauthTests: XCTestCase {

    private var storage: MockPersistentStorable!
    private var keychain: MockKeyStorable!
    private var appleStatus: MockAppleSessionStatus!
    private var analytics: MockAnalyticsTracker!
    private var center: NotificationCenter!
    private var autoReauth: MockAppleSessionAutoReauthenticator!

    private let appleId = "dev@example.com"
    private var signInId: String { ExpiredSignIn.id(of: .appleId(appleId)) }

    override func setUp() async throws {
        try await super.setUp()
        storage = MockPersistentStorable()
        keychain = MockKeyStorable()
        appleStatus = MockAppleSessionStatus()
        analytics = MockAnalyticsTracker()
        center = NotificationCenter()
        autoReauth = MockAppleSessionAutoReauthenticator()
    }

    override func tearDown() async throws {
        storage = nil
        keychain = nil
        appleStatus = nil
        analytics = nil
        center = nil
        autoReauth = nil
        try await super.tearDown()
    }

    private func makeSUT() -> HomeViewModel {
        HomeViewModel(
            storage: storage,
            keychain: keychain,
            preferences: MockKeyStorable(),
            syncService: SyncService(storage: MockPersistentStorable(), keychain: MockKeyStorable(), analytics: MockAnalyticsTracker()),
            teamUsersFetcherFactory: { _ in nil },
            analytics: analytics,
            featureFlags: .googlePlayOn,
            signInExpiry: ExpiredSignInResolver(keychain: keychain, appleStatus: appleStatus, googleStatus: MockGoogleLoginStatus()),
            googleAuth: MockGoogleAuthService(),
            notificationCenter: center,
            autoReauth: autoReauth
        )
    }

    @discardableResult
    private func addAppleSessionAccount(_ name: String, team: UInt64) async throws -> AccountModel {
        let account = AccountModel(name: name, providerType: .apple, authMethod: .appleIdSignIn)
        try await storage.save(account, id: account.id)
        keychain.setObject(
            AppleCredentials(webSession: .init(appleId: appleId, teamId: team, teamName: name)),
            forKey: "credentials.\(account.id)"
        )
        return account
    }

    private func waitUntil(_ condition: @escaping () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<200 where !condition() {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertTrue(condition(), "condition not met in time", file: file, line: line)
    }

    // MARK: - Banner

    func testNoBannerWhileReconnecting() async throws {
        try await addAppleSessionAccount("Team A", team: 1)
        appleStatus.markExpired(appleId: appleId)
        autoReauth.states[appleId] = .reconnecting
        let sut = makeSUT()

        await sut.loadDashboard()

        XCTAssertTrue(sut.uiState.expiredSignIns.isEmpty, "its chips say Reconnecting… instead")
        XCTAssertFalse(sut.uiState.showSignInAgainBanner)
    }

    func testAwaitingCodeSwitchesTheBannerCopy() async throws {
        try await addAppleSessionAccount("Team A", team: 1)
        appleStatus.markExpired(appleId: appleId)
        autoReauth.states[appleId] = .awaitingCode(.trustedDevices)
        let sut = makeSUT()

        await sut.loadDashboard()

        XCTAssertTrue(sut.uiState.showSignInAgainBanner)
        XCTAssertEqual(sut.uiState.awaitingCodeSignIns, [signInId: .trustedDevices])
        XCTAssertEqual(HomeSignInAgainCopy.awaitingCodeTitle, String(localized: "Confirm your Apple account"))
        XCTAssertEqual(HomeSignInAgainCopy.enterCode, String(localized: "Enter Code"))
        XCTAssertEqual(HomeSignInAgainCopy.awaitingCodeMessage(.trustedDevices), String(localized: "Apple sent a code to your devices."))
        XCTAssertEqual(HomeSignInAgainCopy.awaitingCodeMessage(.phone), String(localized: "Apple sent a code to your phone."))
        XCTAssertEqual(HomeSignInAgainCopy.awaitingCodeMessage(.notSent), String(localized: "Apple needs a code to confirm it's you."))
    }

    func testManualBannerWithoutAnAutomaticSignIn() async throws {
        try await addAppleSessionAccount("Team A", team: 1)
        appleStatus.markExpired(appleId: appleId)
        let sut = makeSUT()

        await sut.loadDashboard()

        XCTAssertTrue(sut.uiState.showSignInAgainBanner)
        XCTAssertTrue(sut.uiState.awaitingCodeSignIns.isEmpty)
    }

    func testEnterCodeOpensTheSignInSheetAndTracksIt() async throws {
        try await addAppleSessionAccount("Team A", team: 1)
        appleStatus.markExpired(appleId: appleId)
        autoReauth.states[appleId] = .awaitingCode(.trustedDevices)
        let sut = makeSUT()
        await sut.loadDashboard()

        await sut.startSignInAgain()

        XCTAssertEqual(sut.uiState.signInAgainSheet, .apple(appleId: appleId), "the sheet resumes the code step")
        XCTAssertEqual(analytics.taps(of: .enterCode), [.buttonTap(.enterCode, on: .home)])
        XCTAssertTrue(analytics.taps(of: .signInAgain).isEmpty)
    }

    func testACodeShowsTheClosedBannerAgain() async throws {
        try await addAppleSessionAccount("Team A", team: 1)
        appleStatus.markExpired(appleId: appleId)
        let sut = makeSUT()
        await sut.loadDashboard()
        sut.dismissSignInAgainBanner()

        autoReauth.states[appleId] = .awaitingCode(.trustedDevices)
        autoReauth.send(.finished(appleId: appleId, outcome: .needsCode))

        await waitUntil { sut.uiState.showSignInAgainBanner }
        XCTAssertEqual(sut.uiState.awaitingCodeSignIns, [signInId: .trustedDevices])
    }

    // MARK: - Reconnecting Tip

    /// What the reauthenticator does when an attempt starts: in flight, then
    /// the event.
    private func start(_ appleId: String) {
        autoReauth.states[appleId] = .reconnecting
        autoReauth.send(.started(appleId: appleId))
    }

    /// What the reauthenticator does when an attempt ends: no longer in
    /// flight (or waiting for its code), then the event.
    private func finish(_ appleId: String, _ outcome: AppleSessionAutoReauthOutcome) {
        autoReauth.states[appleId] = outcome == .needsCode ? .awaitingCode(.trustedDevices) : nil
        autoReauth.send(.finished(appleId: appleId, outcome: outcome))
    }

    func testStartedShowsTheReconnectingTipInsteadOfAToast() {
        let sut = makeSUT()

        start(appleId)

        XCTAssertEqual(sut.uiState.reconnectingAppleIds, [appleId])
        XCTAssertNil(sut.uiState.toastMessage, "the tip stays for the whole attempt; no toast")
        XCTAssertEqual(
            HomeReconnectingCopy.text(for: sut.uiState.reconnectingAppleIds),
            String(localized: "Reconnecting Apple ID \(appleId)…")
        )
    }

    func testTheTipNormalizesTheAppleIdAndListsItOnce() {
        let sut = makeSUT()

        start(appleId)
        autoReauth.send(.started(appleId: "  DEV@example.com "))

        XCTAssertEqual(sut.uiState.reconnectingAppleIds, [appleId])
    }

    func testEveryOutcomeRemovesTheTip() {
        for outcome in [AppleSessionAutoReauthOutcome.done, .needsCode, .invalidCredentials, .failed] {
            let sut = makeSUT()
            start(appleId)

            finish(appleId, outcome)

            XCTAssertTrue(sut.uiState.reconnectingAppleIds.isEmpty, "\(outcome)")
        }
    }

    func testOnlyASuccessShowsTheReconnectedToast() {
        for outcome in [AppleSessionAutoReauthOutcome.needsCode, .invalidCredentials, .failed] {
            let sut = makeSUT()
            start(appleId)

            finish(appleId, outcome)

            XCTAssertNil(sut.uiState.toastMessage, "\(outcome)")
        }
    }

    func testTheReconnectedToastHasItsOwnIcon() {
        let sut = makeSUT()
        start(appleId)

        finish(appleId, .done)

        XCTAssertEqual(sut.uiState.toastMessage?.text, String(localized: "Apple account reconnected"))
        XCTAssertEqual(sut.uiState.toastMessage?.icon, "checkmark.circle.fill", "not the sync arrows")
    }

    func testSeveralAppleIdsReconnectTogether() {
        let other = "lead@example.com"
        let sut = makeSUT()

        start(appleId)
        start(other)

        XCTAssertEqual(sut.uiState.reconnectingAppleIds, [appleId, other], "in the order they started")
        XCTAssertEqual(
            HomeReconnectingCopy.text(for: sut.uiState.reconnectingAppleIds),
            String(localized: "Reconnecting \(2) Apple IDs…")
        )

        finish(appleId, .done)

        XCTAssertEqual(sut.uiState.reconnectingAppleIds, [other])
        XCTAssertEqual(
            HomeReconnectingCopy.text(for: sut.uiState.reconnectingAppleIds),
            String(localized: "Reconnecting Apple ID \(other)…")
        )

        finish(other, .failed)

        XCTAssertTrue(sut.uiState.reconnectingAppleIds.isEmpty)
        XCTAssertNil(HomeReconnectingCopy.text(for: sut.uiState.reconnectingAppleIds))
    }

    func testTheTipShowsAnAttemptAlreadyRunningOnLoad() async throws {
        try await addAppleSessionAccount("Team A", team: 1)
        appleStatus.markExpired(appleId: appleId)
        autoReauth.states[appleId] = .reconnecting
        let sut = makeSUT()

        await sut.loadDashboard()

        XCTAssertEqual(sut.uiState.reconnectingAppleIds, [appleId], "started before the Home subscribed")
    }

    func testAReloadKeepsTheTipWhileTheAttemptRuns() async throws {
        try await addAppleSessionAccount("Team A", team: 1)
        appleStatus.markExpired(appleId: appleId)
        let sut = makeSUT()
        start(appleId)

        await sut.loadDashboard()
        await sut.reloadExpiredSignIns()

        XCTAssertEqual(sut.uiState.reconnectingAppleIds, [appleId])
    }

    func testAReloadDropsAnAttemptNoLongerRunning() async throws {
        let sut = makeSUT()
        start(appleId)

        // The attempt ended without its event reaching the Home.
        autoReauth.states[appleId] = nil
        await sut.reloadExpiredSignIns()

        XCTAssertTrue(sut.uiState.reconnectingAppleIds.isEmpty)
    }

    func testSyncAndReconnectShowTogether() async {
        let sut = makeSUT()
        start(appleId)

        sut.uiState.syncState = SyncState(isSyncing: true, accountsInProgress: ["account-1"])

        XCTAssertTrue(sut.uiState.syncState.isSyncing, "the sync line shows")
        XCTAssertEqual(sut.uiState.reconnectingAppleIds, [appleId], "and the reconnecting tip with it")

        // A real sync runs and finishes: the tip stays until the attempt ends.
        sut.triggerSync()
        await waitUntil { sut.uiState.syncState.lastSyncedAt != nil && !sut.uiState.syncState.isSyncing }
        XCTAssertEqual(sut.uiState.reconnectingAppleIds, [appleId])

        finish(appleId, .done)
        XCTAssertTrue(sut.uiState.reconnectingAppleIds.isEmpty)
    }
}
