import XCTest
import StackProtocols
@testable import StackConnect

@MainActor
final class AppPrivacyViewModelTests: XCTestCase {

    private func makeSUT(_ analytics: MockAnalyticsTracker) -> AppPrivacyViewModel {
        AppPrivacyViewModel(
            appId: "app-1",
            account: AccountModel(name: "Team", providerType: .apple),
            keychain: MockKeyStorable(),
            analytics: analytics
        )
    }

    func testLoadTracksNothingAndRefreshTracksFailureWithoutCredentials() async {
        let analytics = MockAnalyticsTracker()
        let sut = makeSUT(analytics)

        await sut.load()
        XCTAssertTrue(analytics.trackedEvents.isEmpty)

        await sut.refresh()
        XCTAssertEqual(analytics.actions(of: .refresh), [.action(.refresh, on: .appPrivacy, result: .failure)])
    }

    func testSaveTracksTapAndFailureWithoutCredentials() async {
        let analytics = MockAnalyticsTracker()
        let sut = makeSUT(analytics)
        let localization = AppPrivacyLocaleState(
            id: "loc-1", locale: "en-US", privacyPolicyUrl: "", privacyChoicesUrl: "", privacyPolicyText: ""
        )

        await sut.save(localization: localization)

        XCTAssertEqual(analytics.trackedEvents, [
            .buttonTap(.save, on: .appPrivacyEdit),
            .action(.updateAppPrivacy, on: .appPrivacyEdit, result: .failure)
        ])
    }
}
