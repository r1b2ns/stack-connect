import XCTest
import StackProtocols
@testable import StackConnect

@MainActor
final class AppReviewDetailViewModelTests: XCTestCase {

    func testResubmitAndDiscardTrackFailureWithoutCredentials() async {
        let analytics = MockAnalyticsTracker()
        let submission = ReviewSubmissionModel(
            id: "sub-1", appId: "app-1", platform: "IOS", submittedDate: nil, state: "READY_FOR_REVIEW",
            versionString: "1.0", versionId: "v1", submittedByName: nil, submittedByEmail: nil
        )
        let sut = AppReviewDetailViewModel(
            submission: submission,
            account: AccountModel(name: "Team", providerType: .apple),
            keychain: MockKeyStorable(),
            analytics: analytics
        )

        await sut.resubmit()
        await sut.discard()

        XCTAssertEqual(analytics.trackedEvents, [
            .action(.submitSubmission, on: .appReviewDetail, result: .failure),
            .action(.discardSubmission, on: .appReviewDetail, result: .failure)
        ])
    }
}
