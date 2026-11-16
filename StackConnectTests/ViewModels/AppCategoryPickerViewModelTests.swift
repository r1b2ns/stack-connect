import XCTest
import StackProtocols
@testable import StackConnect

@MainActor
final class AppCategoryPickerViewModelTests: XCTestCase {

    func testSaveTracksTapAndFailureWithoutCredentials() async {
        let analytics = MockAnalyticsTracker()
        let sut = AppCategoryPickerViewModel(
            appInfoId: "info-1",
            currentCategoryId: "GAMES",
            currentSubcategoryId: nil,
            currentSecondaryCategoryId: nil,
            currentSecondarySubcategoryId: nil,
            account: AccountModel(name: "Team", providerType: .apple),
            keychain: MockKeyStorable(),
            analytics: analytics
        )

        await sut.save()

        XCTAssertEqual(analytics.trackedEvents, [
            .buttonTap(.save, on: .appCategoryPicker),
            .action(.updateCategory, on: .appCategoryPicker, result: .failure)
        ])
    }
}
