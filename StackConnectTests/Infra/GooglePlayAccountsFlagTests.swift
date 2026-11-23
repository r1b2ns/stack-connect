import XCTest
@testable import StackConnect

/// `FeatureFlag.googlePlayAccounts`: remote precedence (stored / launch
/// argument > Remote Config > default OFF) and the provider availability policy.
final class GooglePlayAccountsFlagTests: XCTestCase {

    private var suiteName: String!
    private var defaults: UserDefaults!
    private let remoteKey = "google_play_accounts_enabled"

    override func setUp() {
        super.setUp()
        suiteName = "GooglePlayAccountsFlagTests.\(UUID().uuidString)"
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
        XCTAssertEqual(FeatureFlag.googlePlayAccounts.rawValue, "featureFlag.googlePlayAccounts")
        XCTAssertFalse(FeatureFlag.googlePlayAccounts.defaultValue)
        XCTAssertEqual(FeatureFlag.googlePlayAccounts.remoteConfigKey, remoteKey)
        XCTAssertNil(FeatureFlag.googlePlayReleaseWrites.remoteConfigKey)
        XCTAssertNil(FeatureFlag.useRustCoreDebugLogging.remoteConfigKey)
    }

    // MARK: - Precedence

    func testDefaultsOffWithoutStoredOrRemoteValue() {
        XCTAssertFalse(flags(remote: [:]).isEnabled(.googlePlayAccounts))
    }

    func testRemoteValueTurnsTheFlagOn() {
        XCTAssertTrue(flags(remote: [remoteKey: true]).isEnabled(.googlePlayAccounts))
    }

    func testRemoteFalseKeepsTheFlagOff() {
        XCTAssertFalse(flags(remote: [remoteKey: false]).isEnabled(.googlePlayAccounts))
    }

    func testStoredValueWinsOverRemoteTrue() {
        defaults.set(false, forKey: FeatureFlag.googlePlayAccounts.rawValue)
        XCTAssertFalse(flags(remote: [remoteKey: true]).isEnabled(.googlePlayAccounts))
    }

    func testStoredValueWinsOverRemoteFalse() {
        // A launch argument `-featureFlag.googlePlayAccounts YES` lands here.
        defaults.set(true, forKey: FeatureFlag.googlePlayAccounts.rawValue)
        XCTAssertTrue(flags(remote: [remoteKey: false]).isEnabled(.googlePlayAccounts))
    }

    func testRemoteValueOfAnotherKeyIsIgnored() {
        XCTAssertFalse(flags(remote: ["something_else": true]).isEnabled(.googlePlayAccounts))
    }

    func testRemoteValuesNeverAffectLocalOnlyFlags() {
        let flags = flags(remote: [remoteKey: true, FeatureFlag.googlePlayReleaseWrites.rawValue: true])
        XCTAssertFalse(flags.isEnabled(.googlePlayReleaseWrites))
        XCTAssertFalse(flags.isEnabled(.useRustCoreDebugLogging))
    }

    func testFakeDataSessionDefaultsDoNotTurnTheFlagOn() {
        // The fake data mode only turns `googlePlayReleaseWrites` on.
        FeatureFlags.sessionDefaults = [.googlePlayReleaseWrites: true]
        let flags = flags(remote: [:])
        XCTAssertTrue(flags.isEnabled(.googlePlayReleaseWrites))
        XCTAssertFalse(flags.isEnabled(.googlePlayAccounts))
    }

    func testLaunchRemoteValuesAreUsedWhenNoneIsInjected() {
        let previous = FeatureFlags.launchRemoteValues
        defer { FeatureFlags.launchRemoteValues = previous }

        FeatureFlags.launchRemoteValues = RemoteFeatureValueSnapshot(values: [remoteKey: true])
        XCTAssertTrue(FeatureFlags(defaults: defaults).isEnabled(.googlePlayAccounts))

        FeatureFlags.launchRemoteValues = nil
        XCTAssertFalse(FeatureFlags(defaults: defaults).isEnabled(.googlePlayAccounts),
                       "Firebase not configured: the default (OFF) applies")
    }

    func testSnapshotReturnsOnlyItsValues() {
        let snapshot = RemoteFeatureValueSnapshot(values: [remoteKey: true])
        XCTAssertEqual(snapshot.boolValue(forKey: remoteKey), true)
        XCTAssertNil(snapshot.boolValue(forKey: "absent"))
    }

    // MARK: - Provider availability

    func testHiddenGooglePlayLeavesAppStoreConnectAndFirebase() {
        let flags = FeatureFlags.googlePlayOff
        XCTAssertEqual(flags.availableProviders, [.apple, .firebase])
        XCTAssertFalse(flags.isProviderAvailable(.googlePlay))
        XCTAssertTrue(flags.isProviderAvailable(.apple))
        XCTAssertTrue(flags.isProviderAvailable(.firebase))
    }

    func testVisibleGooglePlayOffersEveryProvider() {
        XCTAssertEqual(FeatureFlags.googlePlayOn.availableProviders, ProviderType.allCases)
    }

    func testVisibleAccountsDropsHiddenStoresInOrder() {
        let accounts = [
            AccountModel(id: "1", name: "a", providerType: .apple),
            AccountModel(id: "2", name: "p", providerType: .googlePlay),
            AccountModel(id: "3", name: "f", providerType: .firebase)
        ]
        XCTAssertEqual(FeatureFlags.googlePlayOff.visibleAccounts(accounts).map(\.id), ["1", "3"])
        XCTAssertEqual(FeatureFlags.googlePlayOn.visibleAccounts(accounts).map(\.id), ["1", "2", "3"])
    }

    func testRootSidebarOrderFollowsTheFlag() {
        XCTAssertEqual(RootSidebarViewModel.visibleProviderOrder(featureFlags: .googlePlayOff), [.apple, .firebase])
        XCTAssertEqual(RootSidebarViewModel.visibleProviderOrder(featureFlags: .googlePlayOn), [.apple, .googlePlay, .firebase])
    }
}
