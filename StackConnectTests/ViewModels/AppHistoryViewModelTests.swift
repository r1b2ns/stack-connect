import XCTest
import StackProtocols
@testable import StackConnect

@MainActor
final class AppHistoryViewModelTests: XCTestCase {

    func testLoadTracksNothingAndRefreshTracksFailureWithoutCredentials() async {
        let analytics = MockAnalyticsTracker()
        let sut = AppHistoryViewModel(
            appId: "app-1",
            account: AccountModel(name: "Team", providerType: .apple),
            keychain: MockKeyStorable(),
            analytics: analytics
        )

        await sut.load()
        XCTAssertTrue(analytics.trackedEvents.isEmpty)

        await sut.refresh()
        XCTAssertEqual(analytics.trackedEvents, [.action(.refresh, on: .appHistory, result: .failure)])
    }
}
