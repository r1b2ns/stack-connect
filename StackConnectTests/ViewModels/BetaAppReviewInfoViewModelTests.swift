import XCTest
import StackProtocols
@testable import StackConnect

@MainActor
final class BetaAppReviewInfoViewModelTests: XCTestCase {

    private var analytics: MockAnalyticsTracker!
    private var sut: BetaAppReviewInfoViewModel!

    override func setUp() async throws {
        try await super.setUp()
        analytics = MockAnalyticsTracker()
        sut = BetaAppReviewInfoViewModel(
            appId: "app-1",
            account: AccountModel(name: "Team", providerType: .apple),
            keychain: MockKeyStorable(),
            analytics: analytics
        )
    }

    override func tearDown() async throws {
        sut = nil
        analytics = nil
        try await super.tearDown()
    }

    func testLoadTracksNothing() async {
        await sut.load()

        XCTAssertTrue(analytics.trackedEvents.isEmpty)
    }

    func testSaveWithValidationErrorsTracksOnlyTheTap() async {
        await sut.save()

        XCTAssertEqual(analytics.taps(of: .save), [.buttonTap(.save, on: .betaAppReviewInfo)])
        XCTAssertTrue(analytics.actions(of: .updateBetaAppReviewInfo).isEmpty)
    }

    func testSaveTracksFailureWithoutCredentials() async {
        sut.uiState.betaDescription = "Beta"
        sut.uiState.feedbackEmail = "qa@example.com"
        sut.uiState.contactFirstName = "Ada"
        sut.uiState.contactLastName = "Lovelace"
        sut.uiState.contactPhone = "+1 555 0100"
        sut.uiState.contactEmail = "ada@example.com"

        await sut.save()

        XCTAssertEqual(analytics.taps(of: .save).count, 1)
        XCTAssertEqual(analytics.actions(of: .updateBetaAppReviewInfo), [
            .action(.updateBetaAppReviewInfo, on: .betaAppReviewInfo, result: .failure)
        ])
    }
}
