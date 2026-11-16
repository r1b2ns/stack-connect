import XCTest
import StackProtocols
@testable import StackConnect

/// Analytics coverage for the bundle ID list / detail ViewModels (no-credentials paths).
@MainActor
final class IdentifiersViewModelsTests: XCTestCase {

    private var analytics: MockAnalyticsTracker!
    private let account = AccountModel(name: "Team", providerType: .apple)
    private let bundle = BundleIdentifierModel(
        id: "bundle-1",
        identifier: "com.example.app",
        name: "Example",
        platform: "IOS",
        seedId: nil
    )

    override func setUp() async throws {
        try await super.setUp()
        analytics = MockAnalyticsTracker()
    }

    override func tearDown() async throws {
        analytics = nil
        try await super.tearDown()
    }

    // MARK: - IdentifiersList

    func testListLoadTracksNothingAndRefreshTracksFailure() async {
        let sut = IdentifiersListViewModel(account: account, keychain: MockKeyStorable(), analytics: analytics)

        await sut.load()
        XCTAssertTrue(analytics.trackedEvents.isEmpty)

        await sut.refresh()
        XCTAssertEqual(analytics.actions(of: .refresh), [.action(.refresh, on: .identifiersList, result: .failure)])
    }

    func testCreateTracksTapAndPlatformOnly() async {
        let sut = IdentifiersListViewModel(account: account, keychain: MockKeyStorable(), analytics: analytics)

        let created = await sut.create(identifier: "com.secret.app", name: "Secret", platformRaw: "MAC_OS")

        XCTAssertFalse(created)
        XCTAssertEqual(analytics.taps(of: .create), [.buttonTap(.create, on: .createBundleId)])
        XCTAssertEqual(analytics.actions(of: .createBundleId), [
            .action(.createBundleId, on: .createBundleId, result: .failure, parameters: [
                AnalyticsParameterKey.kind: .string("MAC_OS")
            ])
        ])
    }

    // MARK: - IdentifierDetail

    func testDetailLoadTracksNothing() async {
        let sut = IdentifierDetailViewModel(account: account, bundleId: bundle, keychain: MockKeyStorable(), analytics: analytics)

        await sut.load()

        XCTAssertTrue(analytics.trackedEvents.isEmpty)
    }

    func testRenameAndDeleteTrackTapAndFailureWithoutCredentials() async {
        let sut = IdentifierDetailViewModel(account: account, bundleId: bundle, keychain: MockKeyStorable(), analytics: analytics)

        _ = await sut.rename(to: "Renamed")
        _ = await sut.delete()

        XCTAssertEqual(analytics.taps(of: .save), [.buttonTap(.save, on: .identifierDetail)])
        XCTAssertEqual(analytics.taps(of: .confirmDelete), [.buttonTap(.confirmDelete, on: .identifierDetail)])
        XCTAssertEqual(analytics.actions(of: .renameBundleId), [.action(.renameBundleId, on: .identifierDetail, result: .failure)])
        XCTAssertEqual(analytics.actions(of: .deleteBundleId), [.action(.deleteBundleId, on: .identifierDetail, result: .failure)])
    }

    func testCapabilityChangesTrackCapabilityTypeOnly() async {
        let sut = IdentifierDetailViewModel(account: account, bundleId: bundle, keychain: MockKeyStorable(), analytics: analytics)
        sut.uiState.capabilities = [BundleIdentifierCapabilityModel(id: "cap-1", capabilityType: "PUSH_NOTIFICATIONS")]

        await sut.enableCapability(typeRaw: "ICLOUD")
        await sut.disableCapability(id: "cap-1")

        XCTAssertEqual(analytics.taps(of: .addCapability), [.buttonTap(.addCapability, on: .addCapability)])
        XCTAssertEqual(analytics.taps(of: .removeCapability), [.buttonTap(.removeCapability, on: .identifierDetail)])
        XCTAssertEqual(analytics.actions(of: .enableCapability), [
            .action(.enableCapability, on: .addCapability, result: .failure, parameters: [
                AnalyticsParameterKey.kind: .string("ICLOUD")
            ])
        ])
        XCTAssertEqual(analytics.actions(of: .disableCapability), [
            .action(.disableCapability, on: .identifierDetail, result: .failure, parameters: [
                AnalyticsParameterKey.kind: .string("PUSH_NOTIFICATIONS")
            ])
        ])
    }
}
