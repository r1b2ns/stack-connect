import XCTest
import StoreKit
@testable import StackConnect

/// The StoreKit-free parts of the tip jar service: result/error mapping,
/// product ordering, the catalog and the background finish rule.
final class TipJarServiceTests: XCTestCase {

    // MARK: - Purchase result mapping

    func testVerifiedIsSuccess() {
        XCTAssertEqual(TipPurchaseOutcomeMapper.outcome(for: .verified), .success)
    }

    func testUnverifiedIsVerificationFailure() {
        XCTAssertEqual(TipPurchaseOutcomeMapper.outcome(for: .unverified), .failed(.verificationFailed))
    }

    func testUserCancelledResultIsUserCancelled() {
        XCTAssertEqual(TipPurchaseOutcomeMapper.outcome(for: .userCancelled), .userCancelled)
    }

    func testPendingResultIsPending() {
        XCTAssertEqual(TipPurchaseOutcomeMapper.outcome(for: .pending), .pending)
    }

    func testUnknownResultIsUnknownFailure() {
        XCTAssertEqual(TipPurchaseOutcomeMapper.outcome(for: .unknown), .failed(.unknown))
    }

    // MARK: - Error mapping

    func testStoreKitUserCancelledErrorIsUserCancelled() {
        XCTAssertEqual(TipPurchaseOutcomeMapper.outcome(for: StoreKitError.userCancelled), .userCancelled)
    }

    func testStoreKitNetworkErrorIsNetworkFailure() {
        let error = StoreKitError.networkError(URLError(.notConnectedToInternet))
        XCTAssertEqual(TipPurchaseOutcomeMapper.outcome(for: error), .failed(.network))
    }

    func testStoreKitNotAvailableInStorefrontIsProductUnavailable() {
        XCTAssertEqual(TipPurchaseOutcomeMapper.outcome(for: StoreKitError.notAvailableInStorefront), .failed(.productUnavailable))
    }

    func testStoreKitNotEntitledIsNotAllowed() {
        XCTAssertEqual(TipPurchaseOutcomeMapper.outcome(for: StoreKitError.notEntitled), .failed(.notAllowed))
    }

    func testStoreKitUnknownErrorIsUnknownFailure() {
        XCTAssertEqual(TipPurchaseOutcomeMapper.outcome(for: StoreKitError.unknown), .failed(.unknown))
    }

    func testPurchaseErrorProductUnavailableIsProductUnavailable() {
        XCTAssertEqual(TipPurchaseOutcomeMapper.outcome(for: Product.PurchaseError.productUnavailable), .failed(.productUnavailable))
    }

    func testPurchaseErrorNotAllowedIsNotAllowed() {
        XCTAssertEqual(TipPurchaseOutcomeMapper.outcome(for: Product.PurchaseError.purchaseNotAllowed), .failed(.notAllowed))
    }

    func testOtherPurchaseErrorIsUnknownFailure() {
        XCTAssertEqual(TipPurchaseOutcomeMapper.outcome(for: Product.PurchaseError.invalidQuantity), .failed(.unknown))
    }

    func testURLErrorIsNetworkFailure() {
        XCTAssertEqual(TipPurchaseOutcomeMapper.outcome(for: URLError(.timedOut)), .failed(.network))
    }

    func testArbitraryErrorIsUnknownFailure() {
        struct SomeError: Error {}
        XCTAssertEqual(TipPurchaseOutcomeMapper.outcome(for: SomeError()), .failed(.unknown))
    }

    // MARK: - Ordering

    func testSortedByPriceIsCheapestFirst() {
        let sorted = TipProduct.sortedByPrice([.lunch, .coffee, .snack])
        XCTAssertEqual(sorted.map(\.id), [TipProduct.coffee.id, TipProduct.snack.id, TipProduct.lunch.id])
    }

    func testSortedByPriceBreaksTiesByProductID() {
        let first = TipProduct.fixture(id: "a", price: 1)
        let second = TipProduct.fixture(id: "b", price: 1)
        XCTAssertEqual(TipProduct.sortedByPrice([second, first]).map(\.id), ["a", "b"])
    }

    // MARK: - Catalog

    func testCatalogHasTheThreeTipProductsCheapestFirst() {
        XCTAssertEqual(TipJarCatalog.productIDs, [
            "zeroSixteen.stackconnect.tip.coffee",
            "zeroSixteen.stackconnect.tip.snack",
            "zeroSixteen.stackconnect.tip.lunch"
        ])
    }

    func testCatalogEmojis() {
        XCTAssertEqual(TipJarCatalog.emoji(for: "zeroSixteen.stackconnect.tip.coffee"), "☕")
        XCTAssertEqual(TipJarCatalog.emoji(for: "zeroSixteen.stackconnect.tip.snack"), "🥪")
        XCTAssertEqual(TipJarCatalog.emoji(for: "zeroSixteen.stackconnect.tip.lunch"), "🍝")
        XCTAssertEqual(TipJarCatalog.emoji(for: "other.product"), "❤️")
    }

    // MARK: - Background transactions

    func testObserverFinishesVerifiedTipTransactions() {
        let ids = Set(TipJarCatalog.productIDs)
        XCTAssertTrue(TipJarTransactionObserver.shouldFinish(productID: TipJarCatalog.Tip.snack.rawValue, isVerified: true, tipProductIDs: ids))
    }

    func testObserverLeavesUnverifiedTransactionsUnfinished() {
        let ids = Set(TipJarCatalog.productIDs)
        XCTAssertFalse(TipJarTransactionObserver.shouldFinish(productID: TipJarCatalog.Tip.snack.rawValue, isVerified: false, tipProductIDs: ids))
    }

    func testObserverIgnoresProductsOutsideTheTipJar() {
        let ids = Set(TipJarCatalog.productIDs)
        XCTAssertFalse(TipJarTransactionObserver.shouldFinish(productID: "other.product", isVerified: true, tipProductIDs: ids))
    }
}
