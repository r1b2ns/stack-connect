import XCTest
@testable import StackConnect

@MainActor
final class HomeViewModelWidgetTests: XCTestCase {

    private var storage: MockPersistentStorable!
    private var preferences: MockKeyStorable!
    private var sut: HomeViewModel!

    override func setUp() async throws {
        try await super.setUp()
        storage = MockPersistentStorable()
        preferences = MockKeyStorable()
        sut = HomeViewModel(
            storage: storage,
            keychain: MockKeyStorable(),
            preferences: preferences,
            syncService: .shared
        )
    }

    override func tearDown() async throws {
        sut = nil
        preferences = nil
        storage = nil
        try await super.tearDown()
    }

    // MARK: - Defaults

    func testDefaultsToRegistryWhenNoStoredConfiguration() {
        XCTAssertEqual(sut.uiState.widgets.count, HomeWidgetRegistry.defaultConfigurations.count)
        XCTAssertEqual(sut.uiState.widgets.first?.kind, .appStoreReviewCount)
    }

    func testLoadsConfigurationsFromPreferences() {
        let stored = [
            HomeWidgetConfiguration(kind: .appStoreReviewCount, size: .compact)
        ]
        preferences.setObject(stored, forKey: "home.widget.configurations")

        let viewModel = HomeViewModel(
            storage: storage,
            keychain: MockKeyStorable(),
            preferences: preferences,
            syncService: .shared
        )

        XCTAssertEqual(viewModel.uiState.widgets.count, 1)
        XCTAssertEqual(viewModel.uiState.widgets.first?.configuration.size, .compact)
    }

    // MARK: - Add

    func testAddWidgetDoesNotDuplicateExistingKind() {
        let initialCount = sut.uiState.widgets.count
        sut.addWidget(.appStoreReviewCount)
        XCTAssertEqual(sut.uiState.widgets.count, initialCount)
    }

    // MARK: - Remove

    func testRemoveWidgetTakesIdAndPersists() {
        guard let widget = sut.uiState.widgets.first else {
            return XCTFail("Expected default widget")
        }
        let id = widget.id

        sut.removeWidget(id: id)

        XCTAssertTrue(sut.uiState.widgets.isEmpty)
        let stored: [HomeWidgetConfiguration]? = preferences.object(forKey: "home.widget.configurations")
        XCTAssertEqual(stored?.count, 0)
    }

    // MARK: - Move

    func testMoveWidgetsReordersAndPersists() {
        sut.removeWidget(id: sut.uiState.widgets[0].id)
        sut.addWidget(.appStoreReviewCount)
        // With only one available kind today, just exercise the call path.
        sut.moveWidgets(from: IndexSet(integer: 0), to: 0)

        let stored: [HomeWidgetConfiguration]? = preferences.object(forKey: "home.widget.configurations")
        XCTAssertEqual(stored?.first?.kind, .appStoreReviewCount)
    }

    // MARK: - Available

    func testAvailableWidgetKindsExcludesActive() {
        let available = sut.availableWidgetKinds()
        let active = sut.uiState.widgets.map { $0.kind }
        for kind in active {
            XCTAssertFalse(available.contains(kind))
        }
    }

    func testAvailableWidgetKindsIncludesEverythingWhenEmpty() {
        for widget in sut.uiState.widgets {
            sut.removeWidget(id: widget.id)
        }
        XCTAssertEqual(Set(sut.availableWidgetKinds()), Set(HomeWidgetKind.allCases))
    }
}
