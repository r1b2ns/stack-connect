import XCTest
import StackProtocols
@testable import StackConnect

/// No credentials are stored, so API-backed actions take their failure path
/// offline; the success path needs a live App Store Connect connection.
@MainActor
final class AppInformationViewModelTests: XCTestCase {

    private var analytics: MockAnalyticsTracker!
    private var sut: AppInformationViewModel!

    override func setUp() async throws {
        try await super.setUp()
        analytics = MockAnalyticsTracker()
        let account = AccountModel(name: "Team", providerType: .apple)
        let app = AppModel(id: "app-1", name: "App", bundleId: "com.app", accountId: account.id)
        sut = AppInformationViewModel(app: app, account: account, keychain: MockKeyStorable(), analytics: analytics)
    }

    override func tearDown() async throws {
        sut = nil
        analytics = nil
        try await super.tearDown()
    }

    func testUpdateContentRightsTracksTapAndFailureWithoutCredentials() async {
        await sut.updateContentRights("DOES_NOT_USE_THIRD_PARTY_CONTENT")

        XCTAssertEqual(analytics.taps(of: .select), [.buttonTap(.select, on: .contentRights)])
        XCTAssertEqual(analytics.actions(of: .updateContentRights), [
            .action(.updateContentRights, on: .contentRights, result: .failure, parameters: [
                AnalyticsParameterKey.kind: .string("DOES_NOT_USE_THIRD_PARTY_CONTENT")
            ])
        ])
    }

    func testUpdatePrimaryLocaleTracksFailureWithoutCredentials() async {
        await sut.updatePrimaryLocale("en-US")

        XCTAssertEqual(analytics.actions(of: .updatePrimaryLocale), [
            .action(.updatePrimaryLocale, on: .appInformation, result: .failure)
        ])
    }

    func testLoadTracksNothing() async {
        await sut.load()

        XCTAssertTrue(analytics.trackedEvents.isEmpty)
    }
}
