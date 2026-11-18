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

    // MARK: - Picker tags (QA: "selection NAVIGATION is invalid")

    private func makeSUT(primary: String?, primarySub: String? = nil, secondary: String?) -> AppCategoryPickerViewModel {
        AppCategoryPickerViewModel(
            appInfoId: "info-1",
            currentCategoryId: primary,
            currentSubcategoryId: primarySub,
            currentSecondaryCategoryId: secondary,
            currentSecondarySubcategoryId: nil,
            account: AccountModel(name: "Team", providerType: .apple),
            keychain: MockKeyStorable(),
            analytics: MockAnalyticsTracker()
        )
    }

    func testStartsLoadingSoTheFormIsNotRenderedWithoutTags() {
        let sut = makeSUT(primary: "NAVIGATION", secondary: "TRAVEL")
        XCTAssertTrue(sut.uiState.isLoading)
        XCTAssertTrue(sut.uiState.categories.isEmpty)
    }

    func testLoadWithoutConnectionFallsBackToFullCatalogContainingSelections() async {
        let sut = makeSUT(primary: "NAVIGATION", primarySub: nil, secondary: "TRAVEL")

        await sut.load()

        let ids = Set(sut.uiState.categories.map(\.id))
        XCTAssertFalse(sut.uiState.isLoading)
        XCTAssertTrue(ids.contains("NAVIGATION"))
        XCTAssertTrue(ids.contains("TRAVEL"))
        XCTAssertEqual(sut.uiState.categories.count, AppStoreCategoryCatalog.all.count)
        XCTAssertEqual(sut.uiState.selectedCategory?.id, "NAVIGATION")
        XCTAssertEqual(sut.uiState.selectedSecondaryCategory?.id, "TRAVEL")
    }

    func testPickerCategoriesAddSelectionsMissingFromTheAPI() {
        let fetched = [AppCategoryModel(id: "BOOKS"), AppCategoryModel(id: "GAMES")]
        let result = AppCategoryPickerViewModel.pickerCategories(
            fetched: fetched,
            selectedIds: ["NAVIGATION", nil, "GAMES", "GAMES_WORD"]
        )
        XCTAssertEqual(result.map(\.id), ["BOOKS", "GAMES", "NAVIGATION"])
        XCTAssertEqual(result.first { $0.id == "GAMES" }?.subcategories.map(\.id), ["GAMES_WORD"])
    }
}
