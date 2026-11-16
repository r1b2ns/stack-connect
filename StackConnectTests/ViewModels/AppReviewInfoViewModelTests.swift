import XCTest
import StackProtocols
@testable import StackConnect

@MainActor
final class AppReviewInfoViewModelTests: XCTestCase {

    func testSaveTracksTapAndFailureWithoutCredentials() async {
        let analytics = MockAnalyticsTracker()
        let sut = AppReviewInfoViewModel(
            versionId: "v1",
            account: AccountModel(name: "Team", providerType: .apple),
            keychain: MockKeyStorable(),
            analytics: analytics
        )
        sut.uiState.reviewDetailId = "detail-1"

        await sut.save()

        XCTAssertEqual(analytics.trackedEvents, [
            .buttonTap(.save, on: .appReviewInfo),
            .action(.updateAppReviewInfo, on: .appReviewInfo, result: .failure)
        ])
    }
}
