import XCTest
import StackProtocols
@testable import StackConnect

/// The `accountConnectionGuide` kill switch and the store that remembers the
/// guide was shown. What the guide does in the account wizard (shown on its
/// own before the first connection only, "How It Works", hidden while OFF) is
/// covered by `AccountWizardViewModelTests`.
@MainActor
final class AddAccountConnectionGuideTests: XCTestCase {

    private var flagSuite: String!
    private var flagDefaults: UserDefaults!
    private var guideSuite: String!
    private var guideDefaults: UserDefaults!

    private let remoteKey = "account_connection_guide_enabled"

    override func setUp() async throws {
        try await super.setUp()
        flagSuite = "AddAccountConnectionGuideTests.flags.\(UUID().uuidString)"
        flagDefaults = UserDefaults(suiteName: flagSuite)
        guideSuite = "AddAccountConnectionGuideTests.guide.\(UUID().uuidString)"
        guideDefaults = UserDefaults(suiteName: guideSuite)
    }

    override func tearDown() async throws {
        flagDefaults.removePersistentDomain(forName: flagSuite)
        guideDefaults.removePersistentDomain(forName: guideSuite)
        flagDefaults = nil
        guideDefaults = nil
        try await super.tearDown()
    }

    // MARK: - Helpers

    /// - Parameters:
    ///   - guide: the stored flag value, or `nil` for none (default or remote).
    ///   - remote: Remote Config values activated at launch.
    private func flags(
        guide: Bool?,
        appleIdSignIn: Bool = true,
        googleSignIn: Bool = true,
        remote: [String: Bool] = [:]
    ) -> FeatureFlags {
        if let guide {
            flagDefaults.set(guide, forKey: FeatureFlag.accountConnectionGuide.rawValue)
        }
        flagDefaults.set(appleIdSignIn, forKey: FeatureFlag.appleIdSignIn.rawValue)
        flagDefaults.set(googleSignIn, forKey: FeatureFlag.googleSignIn.rawValue)
        return FeatureFlags(defaults: flagDefaults, remoteValues: StubRemoteFeatureValues(values: remote))
    }

    private var guideStore: ConnectionGuideStore {
        ConnectionGuideStore(defaults: guideDefaults)
    }

    // MARK: - Flag definition (kill switch)

    func testFlagDefinition() {
        XCTAssertEqual(FeatureFlag.accountConnectionGuide.rawValue, "featureFlag.accountConnectionGuide")
        XCTAssertEqual(FeatureFlag.accountConnectionGuide.remoteConfigKey, remoteKey)
        XCTAssertTrue(FeatureFlag.accountConnectionGuide.defaultValue, "a kill switch ships ON, in every build")
    }

    func testFlagIsOnWithoutStoredOrRemoteValue() {
        XCTAssertTrue(flags(guide: nil).isEnabled(.accountConnectionGuide))
    }

    func testRemoteFalseTurnsTheFlagOff() {
        XCTAssertFalse(flags(guide: nil, remote: [remoteKey: false]).isEnabled(.accountConnectionGuide))
        XCTAssertTrue(flags(guide: nil, remote: [remoteKey: true]).isEnabled(.accountConnectionGuide))
    }

    func testStoredValueWinsOverRemote() {
        // A launch argument `-featureFlag.accountConnectionGuide YES` lands here.
        XCTAssertTrue(flags(guide: true, remote: [remoteKey: false]).isEnabled(.accountConnectionGuide))
    }

    // MARK: - Store

    func testStoreRemembersTheGuideAcrossInstances() {
        XCTAssertFalse(ConnectionGuideStore(defaults: guideDefaults).hasShownGuide)

        ConnectionGuideStore(defaults: guideDefaults).markGuideShown()

        XCTAssertTrue(ConnectionGuideStore(defaults: guideDefaults).hasShownGuide)
        XCTAssertTrue(guideDefaults.bool(forKey: "connectionGuide.hasShownAutomatically"), "stable key")
    }
}
