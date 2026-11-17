import XCTest
import StackProtocols
@testable import StackConnect

@MainActor
final class TipJarViewModelTests: XCTestCase {

    private var service: MockTipJarService!
    private var analytics: MockAnalyticsTracker!
    private var sut: TipJarViewModel!

    override func setUp() async throws {
        try await super.setUp()
        service = MockTipJarService()
        analytics = MockAnalyticsTracker()
        sut = TipJarViewModel(service: service, analytics: analytics)
    }

    override func tearDown() async throws {
        sut = nil
        analytics = nil
        service = nil
        try await super.tearDown()
    }

    // MARK: - Helpers

    private func loadAllTips() async {
        service.loadResult = .success([.lunch, .coffee, .snack])
        await sut.load()
    }

    private func productIds(of action: AnalyticsAction) -> [AnalyticsValue?] {
        analytics.actions(of: action).map { $0.parameters[AnalyticsParameterKey.productId] }
    }

    // MARK: - Initial state

    func testInitialStateIsLoading() {
        XCTAssertEqual(sut.uiState.phase, .loading)
        XCTAssertTrue(sut.uiState.tips.isEmpty)
        XCTAssertFalse(sut.uiState.isPurchasing)
        XCTAssertFalse(sut.uiState.isShowingThankYou)
        XCTAssertFalse(sut.uiState.isPending)
        XCTAssertNil(sut.uiState.errorMessage)
    }

    // MARK: - Load

    func testLoadSuccessShowsTipsSortedByPrice() async {
        await loadAllTips()

        XCTAssertEqual(sut.uiState.phase, .loaded)
        XCTAssertEqual(sut.uiState.tips.map(\.id), [TipProduct.coffee.id, TipProduct.snack.id, TipProduct.lunch.id])
    }

    func testLoadFailureIsUnavailable() async {
        service.loadResult = .failure(MockTipJarService.LoadError())

        await sut.load()

        XCTAssertEqual(sut.uiState.phase, .unavailable)
        XCTAssertTrue(sut.uiState.tips.isEmpty)
    }

    func testLoadWithNoProductsIsUnavailable() async {
        service.loadResult = .success([])

        await sut.load()

        XCTAssertEqual(sut.uiState.phase, .unavailable)
    }

    func testReloadFailureKeepsTipsAlreadyOnScreen() async {
        await loadAllTips()
        service.loadResult = .failure(MockTipJarService.LoadError())

        await sut.load()

        XCTAssertEqual(sut.uiState.phase, .loaded)
        XCTAssertEqual(sut.uiState.tips.count, 3)
    }

    // MARK: - Retry

    func testRetryAfterFailureLoadsTips() async {
        service.loadResult = .failure(MockTipJarService.LoadError())
        await sut.load()
        XCTAssertEqual(sut.uiState.phase, .unavailable)

        service.loadResult = .success([.snack, .coffee])
        await sut.retry()

        XCTAssertEqual(sut.uiState.phase, .loaded)
        XCTAssertEqual(sut.uiState.tips.map(\.id), [TipProduct.coffee.id, TipProduct.snack.id])
        XCTAssertEqual(service.loadCallCount, 2)
        XCTAssertEqual(analytics.taps(of: .tryAgain).count, 1)
    }

    func testRetryThatFailsAgainStaysUnavailable() async {
        service.loadResult = .failure(MockTipJarService.LoadError())
        await sut.load()

        await sut.retry()

        XCTAssertEqual(sut.uiState.phase, .unavailable)
    }

    // MARK: - Purchase outcomes

    func testPurchaseSuccessShowsThankYou() async {
        await loadAllTips()
        service.purchaseOutcome = .success

        await sut.purchase(.snack)

        XCTAssertEqual(service.purchasedProductIDs, [TipProduct.snack.id])
        XCTAssertTrue(sut.uiState.isShowingThankYou)
        XCTAssertNil(sut.uiState.errorMessage)
        XCTAssertFalse(sut.uiState.isPending)
        XCTAssertEqual(analytics.results(of: .purchaseTip), [.success])
        XCTAssertEqual(productIds(of: .purchaseTip), [.string(TipProduct.snack.id)])
    }

    func testDismissThankYouHidesIt() async {
        await loadAllTips()
        await sut.purchase(.coffee)

        sut.dismissThankYou()

        XCTAssertFalse(sut.uiState.isShowingThankYou)
    }

    func testUserCancelledShowsNoErrorAndNoThankYou() async {
        await loadAllTips()
        service.purchaseOutcome = .userCancelled

        await sut.purchase(.coffee)

        XCTAssertNil(sut.uiState.errorMessage)
        XCTAssertFalse(sut.uiState.isShowingThankYou)
        XCTAssertFalse(sut.uiState.isPending)
        XCTAssertEqual(analytics.results(of: .purchaseTip), [.cancelled])
    }

    func testPendingShowsPendingMessage() async {
        await loadAllTips()
        service.purchaseOutcome = .pending

        await sut.purchase(.lunch)

        XCTAssertTrue(sut.uiState.isPending)
        XCTAssertFalse(sut.uiState.isShowingThankYou)
        XCTAssertNil(sut.uiState.errorMessage)
        XCTAssertEqual(analytics.results(of: .purchaseTip), [.pending])
    }

    func testNewPurchaseClearsPreviousPending() async {
        await loadAllTips()
        service.purchaseOutcome = .pending
        await sut.purchase(.lunch)

        service.purchaseOutcome = .success
        await sut.purchase(.coffee)

        XCTAssertFalse(sut.uiState.isPending)
        XCTAssertTrue(sut.uiState.isShowingThankYou)
    }

    func testFailureShowsError() async {
        await loadAllTips()
        service.purchaseOutcome = .failed(.network)

        await sut.purchase(.coffee)

        XCTAssertEqual(sut.uiState.errorMessage, TipJarViewModel.message(for: .network))
        XCTAssertFalse(sut.uiState.isShowingThankYou)
        XCTAssertEqual(analytics.results(of: .purchaseTip), [.failure])
    }

    func testDismissErrorClearsIt() async {
        await loadAllTips()
        service.purchaseOutcome = .failed(.unknown)
        await sut.purchase(.coffee)

        sut.dismissError()

        XCTAssertNil(sut.uiState.errorMessage)
    }

    func testEveryFailureHasAMessage() {
        let failures: [TipPurchaseFailure] = [.productUnavailable, .notAllowed, .network, .verificationFailed, .unknown]
        let messages = failures.map(TipJarViewModel.message(for:))

        XCTAssertFalse(messages.contains(where: \.isEmpty))
        XCTAssertEqual(Set(messages).count, failures.count)
    }

    // MARK: - Purchasing flag

    func testPurchasingFlagIsSetWhilePurchaseIsInFlight() async {
        await loadAllTips()
        let gate = AsyncGate()
        service.purchaseGate = gate

        let purchase = Task { await sut.purchase(.snack) }
        await gate.waitForArrivals()

        XCTAssertTrue(sut.uiState.isPurchasing)
        XCTAssertEqual(sut.uiState.purchasingProductID, TipProduct.snack.id)

        await gate.open()
        await purchase.value

        XCTAssertFalse(sut.uiState.isPurchasing)
        XCTAssertNil(sut.uiState.purchasingProductID)
    }

    func testPurchasingFlagIsClearedAfterFailure() async {
        await loadAllTips()
        service.purchaseOutcome = .failed(.unknown)

        await sut.purchase(.coffee)

        XCTAssertFalse(sut.uiState.isPurchasing)
    }

    func testSecondPurchaseIsIgnoredWhileOneIsInFlight() async {
        await loadAllTips()
        let gate = AsyncGate()
        service.purchaseGate = gate

        let first = Task { await sut.purchase(.snack) }
        await gate.waitForArrivals()

        await sut.purchase(.coffee)
        XCTAssertEqual(service.purchasedProductIDs, [TipProduct.snack.id])

        await gate.open()
        await first.value

        XCTAssertEqual(analytics.taps(of: .purchaseTip).count, 1)
    }

    // MARK: - Analytics

    func testPurchaseTracksTapOnTipJar() async {
        await loadAllTips()

        await sut.purchase(.coffee)

        let taps = analytics.taps(of: .purchaseTip)
        XCTAssertEqual(taps.count, 1)
        XCTAssertEqual(taps.first?.parameters[AnalyticsParameterKey.screenName], .string(AnalyticsScreen.tipJar.rawValue))
    }

    func testPurchaseSendsNothingWhenAnalyticsIsOff() async {
        analytics = MockAnalyticsTracker(isEnabled: false)
        sut = TipJarViewModel(service: service, analytics: analytics)
        await loadAllTips()

        await sut.purchase(.coffee)

        XCTAssertTrue(analytics.trackedEvents.isEmpty)
        XCTAssertTrue(sut.uiState.isShowingThankYou)
    }
}
