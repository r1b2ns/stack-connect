import XCTest
import StackProtocols
@testable import StackConnect

@MainActor
final class AgeRatingViewModelTests: XCTestCase {

    func testSaveTracksTapAndFailureWithoutCredentials() async {
        let analytics = MockAnalyticsTracker()
        let sut = AgeRatingViewModel(
            ageRating: AgeRatingDeclarationModel(id: "age-1"),
            account: AccountModel(name: "Team", providerType: .apple),
            keychain: MockKeyStorable(),
            analytics: analytics
        )

        await sut.save()

        XCTAssertEqual(analytics.trackedEvents, [
            .buttonTap(.save, on: .ageRating),
            .action(.updateAgeRating, on: .ageRating, result: .failure)
        ])
    }
}
