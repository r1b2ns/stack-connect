import XCTest
import StackProtocols
@testable import StackConnect

/// `FeatureFlag.appleIdSignIn`: remote precedence (stored / launch argument >
/// Remote Config > session default > compiled default — ON in Debug, OFF in
/// Release).
///
/// The flag ONLY hides adding NEW App Store Connect accounts with email and
/// password: accounts already added with `.appleIdSignIn` keep reconnecting
/// and syncing when it is OFF (remote `false` or a stored `false`).
final class AppleIdSignInFlagTests: XCTestCase {

    private var suiteName: String!
    private var defaults: UserDefaults!
    private let remoteKey = "apple_id_sign_in_enabled"

    override func setUp() {
        super.setUp()
        suiteName = "AppleIdSignInFlagTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        FeatureFlags.sessionDefaults = [:]
        super.tearDown()
    }

    private func flags(remote: [String: Bool]) -> FeatureFlags {
        FeatureFlags(defaults: defaults, remoteValues: StubRemoteFeatureValues(values: remote))
    }

    // MARK: - Definition

    func testFlagDefinition() {
        XCTAssertEqual(FeatureFlag.appleIdSignIn.rawValue, "featureFlag.appleIdSignIn")
        XCTAssertEqual(FeatureFlag.appleIdSignIn.remoteConfigKey, remoteKey)
        #if DEBUG
        XCTAssertTrue(FeatureFlag.appleIdSignIn.defaultValue)
        #else
        XCTAssertFalse(FeatureFlag.appleIdSignIn.defaultValue)
        #endif
    }

    // MARK: - Precedence

    func testAbsentRemoteValueKeepsTheCompiledDefault() {
        XCTAssertEqual(flags(remote: [:]).isEnabled(.appleIdSignIn), FeatureFlag.appleIdSignIn.defaultValue)
    }

    func testRemoteTrueTurnsTheFlagOn() {
        XCTAssertTrue(flags(remote: [remoteKey: true]).isEnabled(.appleIdSignIn))
    }

    func testRemoteFalseTurnsTheFlagOff() {
        // In Debug the compiled default is ON: remote `false` still hides it.
        XCTAssertFalse(flags(remote: [remoteKey: false]).isEnabled(.appleIdSignIn))
    }

    func testStoredValueWinsOverRemoteTrue() {
        defaults.set(false, forKey: FeatureFlag.appleIdSignIn.rawValue)
        XCTAssertFalse(flags(remote: [remoteKey: true]).isEnabled(.appleIdSignIn))
    }

    func testStoredValueWinsOverRemoteFalse() {
        // A launch argument `-featureFlag.appleIdSignIn YES` lands here.
        defaults.set(true, forKey: FeatureFlag.appleIdSignIn.rawValue)
        XCTAssertTrue(flags(remote: [remoteKey: false]).isEnabled(.appleIdSignIn))
    }

    func testRemoteValueWinsOverSessionDefault() {
        FeatureFlags.sessionDefaults = [.appleIdSignIn: true]
        XCTAssertFalse(flags(remote: [remoteKey: false]).isEnabled(.appleIdSignIn))
        XCTAssertTrue(flags(remote: [:]).isEnabled(.appleIdSignIn))
    }

    func testRemoteValueOfAnotherKeyIsIgnored() {
        XCTAssertEqual(flags(remote: ["something_else": !FeatureFlag.appleIdSignIn.defaultValue])
            .isEnabled(.appleIdSignIn), FeatureFlag.appleIdSignIn.defaultValue)
    }

    func testRemoteKeyDoesNotAffectOtherFlags() {
        let flags = flags(remote: [remoteKey: false])
        XCTAssertEqual(flags.isEnabled(.googleSignIn), FeatureFlag.googleSignIn.defaultValue)
        XCTAssertFalse(flags.isEnabled(.googlePlayAccounts))
    }

    func testLaunchRemoteValuesAreUsedWhenNoneIsInjected() {
        let previous = FeatureFlags.launchRemoteValues
        defer { FeatureFlags.launchRemoteValues = previous }

        FeatureFlags.launchRemoteValues = RemoteFeatureValueSnapshot(values: [remoteKey: true])
        XCTAssertTrue(FeatureFlags(defaults: defaults).isEnabled(.appleIdSignIn))

        FeatureFlags.launchRemoteValues = RemoteFeatureValueSnapshot(values: [remoteKey: false])
        XCTAssertFalse(FeatureFlags(defaults: defaults).isEnabled(.appleIdSignIn))

        FeatureFlags.launchRemoteValues = nil
        XCTAssertEqual(FeatureFlags(defaults: defaults).isEnabled(.appleIdSignIn),
                       FeatureFlag.appleIdSignIn.defaultValue,
                       "Firebase not configured: the compiled default applies")
    }

    // MARK: - Account wizard

    func testRemoteValueDrivesTheAppStoreConnectMethods() {
        func methods(remote: [String: Bool]) -> [AccountWizardMethod]? {
            AccountWizardConfig.make(entry: .chooseKind,
                                     featureFlags: flags(remote: remote),
                                     isGoogleSignInConfigured: true)
                .kindConfig(for: .provider(.apple))?.methods
        }
        XCTAssertEqual(methods(remote: [remoteKey: true]), [.apiKey, .appleIdSignIn])
        XCTAssertEqual(methods(remote: [remoteKey: false]), [.apiKey])
    }

    // MARK: - Flag OFF: new accounts only

    /// Both ways the flag ends up OFF: remote `false`, and a stored `false`
    /// that wins over remote `true`.
    private func flagsOff() -> [(label: String, flags: FeatureFlags)] {
        let remoteOff = flags(remote: [remoteKey: false])
        let suite = "AppleIdSignInFlagTests.stored.\(UUID().uuidString)"
        let stored = UserDefaults(suiteName: suite) ?? .standard
        stored.removePersistentDomain(forName: suite)
        stored.set(false, forKey: FeatureFlag.appleIdSignIn.rawValue)
        addTeardownBlock { stored.removePersistentDomain(forName: suite) }
        let storedOff = FeatureFlags(defaults: stored, remoteValues: StubRemoteFeatureValues(values: [remoteKey: true]))
        return [("remote false", remoteOff), ("stored false", storedOff)]
    }

    private var appleIdAccount: AccountModel {
        AccountModel(name: "Personal", providerType: .apple, authMethod: .appleIdSignIn)
    }

    func testNewAppStoreConnectAccountOffersOnlyTheApiKeyWhileOff() {
        for (label, flags) in flagsOff() {
            XCTAssertFalse(flags.isEnabled(.appleIdSignIn), label)
            let config = AccountWizardConfig.make(entry: .kind(.provider(.apple)),
                                                  featureFlags: flags,
                                                  isGoogleSignInConfigured: true)
            XCTAssertEqual(config.initialKind?.methods, [.apiKey], label)
            XCTAssertEqual(config.initialMethod, .apiKey, label)
            XCTAssertEqual(AccountWizardFlow.steps(entry: config.entry, kind: config.initialKind, method: config.initialMethod),
                           [.credentials, .review], "\(label): no Method step, no email and password")
        }
    }

    func testExistingAppleIdAccountKeepsItsReconnectMethodWhileOff() {
        let account = appleIdAccount
        XCTAssertTrue(AccountWizardConfig.canReconnect(account))
        XCTAssertEqual(AccountWizardConfig.reconnectMethod(for: account), .appleIdSignIn)
        XCTAssertEqual(AccountWizardConfig.reconnectKind(for: account)?.kind, .provider(.apple))
        XCTAssertEqual(AccountWizardConfig.reconnectKind(for: account)?.methods, [.appleIdSignIn])

        for (label, flags) in flagsOff() {
            let config = AccountWizardConfig.make(entry: .reconnect(account),
                                                  featureFlags: flags,
                                                  isGoogleSignInConfigured: true)
            XCTAssertEqual(config.initialKind?.methods, [.appleIdSignIn], label)
            XCTAssertEqual(config.initialMethod, .appleIdSignIn, label)
            XCTAssertEqual(AccountWizardFlow.steps(entry: config.entry, kind: config.initialKind, method: config.initialMethod),
                           [.credentials, .code], label)
        }
    }

    func testExistingAppleIdAccountStaysVisibleWhileOff() {
        let account = appleIdAccount
        let apiKey = AccountModel(name: "Key", providerType: .apple)
        for (label, flags) in flagsOff() {
            XCTAssertEqual(flags.visibleAccounts([account, apiKey]).map(\.id), [account.id, apiKey.id], label)
        }
    }

    @MainActor
    func testReconnectWizardRunsTheAppleIdSignInWhileOff() async {
        for (label, flags) in flagsOff() {
            let storage = MockPersistentStorable()
            let keychain = MockKeyStorable()
            let analytics = MockAnalyticsTracker()
            let appleFlow = MockAppleIdSignIn()
            let account = appleIdAccount
            keychain.setObject(
                AppleCredentials(webSession: AppleWebSessionReference(appleId: "dev@example.com", teamId: 1, teamName: "Acme")),
                forKey: "credentials.\(account.id)"
            )
            appleFlow.startResults = [.success(.needsCode(methods: [.trustedDevice], phones: [], codeLength: 6, delivery: .trustedDevices))]
            appleFlow.submitResults = [.success(.done(teams: [.fixture(1, "Acme")]))]
            var appleModes: [AppleIdSignInMode] = []
            var connectionsMade = 0
            var syncRequests = 0

            let sut = AccountWizardViewModel(
                entry: .reconnect(account),
                storage: storage,
                keychain: keychain,
                analytics: analytics,
                featureFlags: flags,
                googleAuth: MockGoogleAuthService(),
                connectionGuide: ConnectionGuideStore(defaults: UserDefaults(suiteName: "AppleIdSignInFlagTests.guide.\(UUID().uuidString)") ?? .standard),
                makeConnection: { provider, mode in
                    connectionsMade += 1
                    return AddAccountViewModel(
                        providerType: provider,
                        storage: storage,
                        keychain: keychain,
                        googlePlayConnectionFactory: { _ in MockGooglePlayAccountConnection() },
                        analytics: analytics,
                        featureFlags: flags,
                        googleAuth: MockGoogleAuthService(),
                        googleResources: MockGoogleResourceListing(),
                        credentialMode: mode
                    )
                },
                makeAppleSignIn: { mode in
                    appleModes.append(mode)
                    return AppleIdSignInViewModel(
                        mode: mode,
                        storage: storage,
                        keychain: keychain,
                        sessionStatus: MockAppleSessionStatus(),
                        roleResolver: MockAppleSessionRoleResolver(),
                        analytics: analytics,
                        featureFlags: flags,
                        makeSignIn: { _ in appleFlow }
                    )
                },
                requestSync: { syncRequests += 1 }
            )

            XCTAssertEqual(sut.uiState.step, .credentials, label)
            XCTAssertEqual(sut.uiState.steps, [.credentials, .code], label)
            XCTAssertEqual(appleModes, [.signInAgain(appleId: "dev@example.com")], label)
            XCTAssertNotNil(sut.appleSignIn, label)
            XCTAssertEqual(connectionsMade, 0, "\(label): never the API key form")

            sut.appleSignIn?.uiState.password = "secret"
            await sut.primaryAction()
            XCTAssertEqual(sut.uiState.step, .code, label)
            await sut.appleSignIn?.updateCode("123456")

            XCTAssertEqual(sut.uiState.result, AccountWizardResult(provider: .apple, names: ["Personal"], isReconnect: true), label)
            XCTAssertEqual(syncRequests, 1, label)
        }
    }

    @MainActor
    func testSyncServiceStillSyncsAnAppleIdAccountWhileOff() async throws {
        for (label, flags) in flagsOff() {
            for mode in [SyncMode.full, .lightweight] {
                let storage = MockPersistentStorable()
                let keychain = MockKeyStorable()
                let account = appleIdAccount
                try await storage.save(account, id: account.id)
                keychain.setObject(
                    AppleCredentials(webSession: AppleWebSessionReference(appleId: "dev@example.com", teamId: 1, teamName: "Acme")),
                    forKey: "credentials.\(account.id)"
                )
                let connection = MockAppleAccountSyncing()
                connection.apps = [StackProtocols.AppInfo(id: "app-1", name: "App One", bundleId: "com.one", platform: nil)]
                let analytics = MockAnalyticsTracker()
                let trackerSuite = "AppleIdSignInFlagTests.firstApps.\(UUID().uuidString)"
                addTeardownBlock { UserDefaults.standard.removePersistentDomain(forName: trackerSuite) }
                let sut = StackConnect.SyncService(
                    storage: storage,
                    keychain: keychain,
                    appleConnectionFactory: { _ in connection },
                    widgetSnapshotWriter: { _ in },
                    firstAppsLoaded: FirstAppsLoadedTracker(defaults: UserDefaults(suiteName: trackerSuite) ?? .standard,
                                                            analytics: analytics),
                    analytics: analytics,
                    appleSessionStatus: MockAppleSessionStatus(),
                    featureFlags: flags
                )

                await sut.syncAll(mode: mode).value

                let context = "\(label), \(mode)"
                XCTAssertEqual(sut.state.lastRunAccountCount, 1, context)
                XCTAssertEqual(sut.state.providerByAccountId[account.id], .apple, context)
                XCTAssertEqual(connection.fetchedAppListCount, 1, context)
                let metadata: SyncMetadata? = try await storage.fetch(SyncMetadata.self, id: "sync.account.\(account.id)")
                XCTAssertNil(metadata?.lastError, context)
                XCTAssertEqual(metadata?.appsSynced, 1, context)
            }
        }
    }
}
