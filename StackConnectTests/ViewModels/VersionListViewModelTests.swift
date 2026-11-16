import XCTest
import StackProtocols
@testable import StackConnect

@MainActor
final class VersionListViewModelTests: XCTestCase {

    func testLoadTracksNothingAndRefreshTracksFailureWithoutCredentials() async {
        let analytics = MockAnalyticsTracker()
        let sut = VersionListViewModel(
            appId: "app-1",
            platform: .ios,
            account: AccountModel(name: "Team", providerType: .apple),
            storage: MockPersistentStorable(),
            keychain: MockKeyStorable(),
            analytics: analytics
        )

        await sut.loadVersions()
        XCTAssertTrue(analytics.trackedEvents.isEmpty)

        await sut.refresh()
        XCTAssertEqual(analytics.trackedEvents, [.action(.refresh, on: .versionList, result: .failure)])
    }
}
