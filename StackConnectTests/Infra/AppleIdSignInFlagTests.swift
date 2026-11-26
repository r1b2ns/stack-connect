import XCTest
@testable import StackConnect

/// `FeatureFlag.appleIdSignIn`: remote precedence (stored / launch argument >
/// Remote Config > session default > compiled default — ON in Debug, OFF in
/// Release).
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
}
