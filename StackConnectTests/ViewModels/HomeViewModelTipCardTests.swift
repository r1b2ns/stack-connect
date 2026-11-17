import XCTest
import StackProtocols
@testable import StackConnect

/// The Home "support the project" card: visibility follows
/// `TipJarPromptService`, and tapping or closing it retires it and tracks it.
@MainActor
final class HomeViewModelTipCardTests: XCTestCase {

    private let suiteName = "HomeViewModelTipCardTests.\(UUID().uuidString)"
    private lazy var defaults: UserDefaults = UserDefaults(suiteName: suiteName) ?? .standard

    private var analytics: MockAnalyticsTracker!
    private var tipCard: TipJarPromptService!

    override func setUp() async throws {
        try await super.setUp()
        analytics = MockAnalyticsTracker()
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        tipCard = nil
        analytics = nil
        try await super.tearDown()
    }

    private func makeSUT(isForced: Bool = false) -> HomeViewModel {
        tipCard = TipJarPromptService(defaults: defaults, isEnabled: true, isForced: isForced)
        return HomeViewModel(
            storage: MockPersistentStorable(),
            keychain: MockKeyStorable(),
            preferences: MockKeyStorable(),
            syncService: .shared,
            teamUsersFetcherFactory: { _ in nil },
            analytics: analytics,
            tipCard: tipCard
        )
    }

    private func makeCardEligible() {
        tipCard.evaluateAfterSync(syncSucceeded: true, launchCount: 10, reviewRequestedThisLaunch: false)
    }

    // MARK: - Visibility

    func testCardIsHiddenByDefault() {
        let sut = makeSUT()
        XCTAssertFalse(sut.uiState.showTipCard)
    }

    func testCardShowsOnceEligible() {
        let sut = makeSUT()

        makeCardEligible()

        XCTAssertTrue(sut.uiState.showTipCard)
    }

    func testForcedCardShowsRightAway() {
        let sut = makeSUT(isForced: true)
        XCTAssertTrue(sut.uiState.showTipCard)
    }

    func testCardStaysHiddenWhenIneligible() {
        let sut = makeSUT()

        tipCard.evaluateAfterSync(syncSucceeded: true, launchCount: 9, reviewRequestedThisLaunch: false)

        XCTAssertFalse(sut.uiState.showTipCard)
    }

    func testCompletedTipHidesTheCard() {
        let sut = makeSUT()
        makeCardEligible()

        tipCard.recordCompletedTip()

        XCTAssertFalse(sut.uiState.showTipCard)
    }

    // MARK: - Actions

    func testDismissHidesRetiresAndTracks() {
        let sut = makeSUT()
        makeCardEligible()

        sut.dismissTipCard()

        XCTAssertFalse(sut.uiState.showTipCard)
        XCTAssertTrue(tipCard.hasRetiredCard)
        XCTAssertEqual(analytics.taps(of: .dismissTipCard), [.buttonTap(.dismissTipCard, on: .home)])
        XCTAssertTrue(analytics.taps(of: .openTipCard).isEmpty)
    }

    func testOpenHidesRetiresAndTracks() {
        let sut = makeSUT()
        makeCardEligible()

        sut.openTipCard()

        XCTAssertFalse(sut.uiState.showTipCard)
        XCTAssertTrue(tipCard.hasRetiredCard)
        XCTAssertEqual(analytics.taps(of: .openTipCard), [.buttonTap(.openTipCard, on: .home)])
        XCTAssertTrue(analytics.taps(of: .dismissTipCard).isEmpty)
    }

    func testRetiredCardDoesNotComeBackOnALaterSync() {
        let sut = makeSUT()
        makeCardEligible()
        sut.dismissTipCard()

        makeCardEligible()

        XCTAssertFalse(sut.uiState.showTipCard)
    }
}
