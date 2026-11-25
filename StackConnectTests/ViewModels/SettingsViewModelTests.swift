import XCTest
import StackProtocols
@testable import StackConnect

@MainActor
final class SettingsViewModelTests: XCTestCase {

    private func makeSUT(
        storage: MockPersistentStorable = MockPersistentStorable(),
        keychain: MockKeyStorable = MockKeyStorable(),
        analytics: MockAnalyticsTracker = MockAnalyticsTracker()
    ) -> (SettingsViewModel, AppSettings, UserDefaults, String) {
        let suite = "SettingsViewModelTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let appSettings = AppSettings(defaults: defaults)
        let sut = SettingsViewModel(
            storage: storage,
            keychain: keychain,
            appSettings: appSettings,
            analytics: analytics
        )
        return (sut, appSettings, defaults, suite)
    }

    func testPreReviewChecklistDefaultsToEnabled() {
        let (sut, _, defaults, suite) = makeSUT()
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertTrue(sut.uiState.preReviewChecklistEnabled)
    }

    func testTogglePersistsToAppSettings() {
        let (sut, appSettings, defaults, suite) = makeSUT()
        defer { defaults.removePersistentDomain(forName: suite) }

        sut.setPreReviewChecklistEnabled(false)

        XCTAssertFalse(sut.uiState.preReviewChecklistEnabled)
        XCTAssertFalse(appSettings.isEnabled(.preReviewChecklistEnabled))
    }

    // MARK: - Usage analytics

    func testAnalyticsInitialStateReflectsEnabledTracker() {
        let (sut, _, defaults, suite) = makeSUT(analytics: MockAnalyticsTracker(isEnabled: true))
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertTrue(sut.uiState.analyticsEnabled)
    }

    func testAnalyticsInitialStateReflectsDisabledTracker() {
        let (sut, _, defaults, suite) = makeSUT(analytics: MockAnalyticsTracker(isEnabled: false))
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertFalse(sut.uiState.analyticsEnabled)
    }

    func testTurningAnalyticsOffForwardsToTracker() {
        let tracker = MockAnalyticsTracker(isEnabled: true)
        let (sut, _, defaults, suite) = makeSUT(analytics: tracker)
        defer { defaults.removePersistentDomain(forName: suite) }

        sut.setAnalyticsEnabled(false)

        XCTAssertEqual(tracker.setEnabledCalls, [false])
        XCTAssertFalse(sut.uiState.analyticsEnabled)
    }

    func testTurningAnalyticsOnForwardsToTracker() {
        let tracker = MockAnalyticsTracker(isEnabled: false)
        let (sut, _, defaults, suite) = makeSUT(analytics: tracker)
        defer { defaults.removePersistentDomain(forName: suite) }

        sut.setAnalyticsEnabled(true)

        XCTAssertEqual(tracker.setEnabledCalls, [true])
        XCTAssertTrue(sut.uiState.analyticsEnabled)
    }

    func testViewModelDoesNotWriteTheAnalyticsSettingItself() {
        let (sut, _, defaults, suite) = makeSUT(analytics: MockAnalyticsTracker(isEnabled: true))
        defer { defaults.removePersistentDomain(forName: suite) }

        sut.setAnalyticsEnabled(false)

        XCTAssertNil(defaults.object(forKey: AppSetting.analyticsEnabled.rawValue))
    }

    func testTurningAnalyticsOffThroughRealServiceSendsOnlyTheDisabledEvent() {
        let suite = "SettingsViewModelTests.analytics.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        let provider = MockAnalyticsProvider()
        let service = AnalyticsService(providers: [provider], settings: settings)
        let sut = SettingsViewModel(
            storage: MockPersistentStorable(),
            keychain: MockKeyStorable(),
            appSettings: settings,
            analytics: service
        )

        sut.setAnalyticsEnabled(false)
        service.track(.screenView(.settings))

        XCTAssertEqual(provider.sentEventNames, ["analytics_disabled"])
        XCTAssertFalse(sut.uiState.analyticsEnabled)
        XCTAssertFalse(settings.isEnabled(.analyticsEnabled))
    }

    // MARK: - Accounts summary

    func testAccountsSummaryCountsTheVisibleAccountsByStoreAndThoseNeedingAttention() async throws {
        let storage = MockPersistentStorable()
        let statuses = MockAccountStatusProvider()
        let accounts = [
            AccountModel(name: "Key", providerType: .apple),
            AccountModel(name: "Session", providerType: .apple, authMethod: .appleIdSignIn),
            AccountModel(name: "Fire", providerType: .firebase),
            AccountModel(name: "Play", providerType: .googlePlay)
        ]
        for account in accounts { try await storage.save(account, id: account.id) }
        statuses.statusesById = [accounts[1].id: .of(.signInExpired), accounts[3].id: .of(.pendingAgreements)]
        let sut = SettingsViewModel(storage: storage, keychain: MockKeyStorable(), analytics: MockAnalyticsTracker(),
                                    featureFlags: .googlePlayOff, statusProvider: statuses, notificationCenter: NotificationCenter())

        await sut.loadAccountsSummary()

        let summary = sut.uiState.accountsSummary
        XCTAssertEqual(summary.total, 3, "Hidden Google Play accounts aren't counted")
        XCTAssertEqual(summary.needsAttention, 1)
        XCTAssertEqual(summary.providers, [.init(provider: .apple, count: 2), .init(provider: .firebase, count: 1)])
    }

    func testAccountsSummaryIsEmptyWithoutAccounts() async {
        let sut = SettingsViewModel(storage: MockPersistentStorable(), keychain: MockKeyStorable(), analytics: MockAnalyticsTracker(),
                                    featureFlags: .googlePlayOn, statusProvider: MockAccountStatusProvider(), notificationCenter: NotificationCenter())

        await sut.loadAccountsSummary()

        XCTAssertEqual(sut.uiState.accountsSummary, .empty)
    }

    func testAccountsSummaryReloadsWhenAccountsChange() async throws {
        let storage = MockPersistentStorable()
        let center = NotificationCenter()
        let sut = SettingsViewModel(storage: storage, keychain: MockKeyStorable(), analytics: MockAnalyticsTracker(),
                                    featureFlags: .googlePlayOn, statusProvider: MockAccountStatusProvider(), notificationCenter: center)
        await sut.loadAccountsSummary()
        try await storage.save(AccountModel(name: "New", providerType: .apple), id: "new")

        AccountsChange.post(center: center)
        try await Task.sleep(for: .milliseconds(150))

        XCTAssertEqual(sut.uiState.accountsSummary.total, 1)
    }

    // MARK: - Analytics events

    func testTogglingPreReviewChecklistTracksTheNewValue() {
        let tracker = MockAnalyticsTracker()
        let (sut, _, defaults, suite) = makeSUT(analytics: tracker)
        defer { defaults.removePersistentDomain(forName: suite) }

        sut.setPreReviewChecklistEnabled(false)

        XCTAssertEqual(tracker.trackedEvents, [
            .action(.togglePreReviewChecklist, on: .settings, parameters: [AnalyticsParameterKey.enabled: .bool(false)])
        ])
    }
}
