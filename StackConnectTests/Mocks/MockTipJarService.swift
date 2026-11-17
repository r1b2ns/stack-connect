import Foundation
@testable import StackConnect

/// In-memory `TipJarServiceProtocol`. Set `loadResult` / `purchaseOutcome`
/// before acting; `purchaseGate` holds a purchase mid-flight so a test can
/// observe the purchasing state.
@MainActor
final class MockTipJarService: TipJarServiceProtocol {

    struct LoadError: Error {}

    var loadResult: Result<[TipProduct], Error> = .success([])
    var purchaseOutcome: TipPurchaseOutcome = .success
    var purchaseGate: AsyncGate?

    private(set) var loadCallCount = 0
    private(set) var purchasedProductIDs: [String] = []

    func loadProducts() async throws -> [TipProduct] {
        loadCallCount += 1
        return try loadResult.get()
    }

    func purchase(productID: String) async -> TipPurchaseOutcome {
        purchasedProductIDs.append(productID)
        if let purchaseGate {
            await purchaseGate.wait()
        }
        return purchaseOutcome
    }
}

extension TipProduct {
    static func fixture(
        id: String = TipJarCatalog.Tip.coffee.rawValue,
        displayName: String = "Coffee",
        description: String = "Buy the developer a coffee.",
        displayPrice: String = "$0.99",
        price: Decimal = Decimal(99) / 100
    ) -> TipProduct {
        TipProduct(id: id, displayName: displayName, description: description, displayPrice: displayPrice, price: price)
    }

    static let coffee = TipProduct.fixture()
    static let snack = TipProduct.fixture(
        id: TipJarCatalog.Tip.snack.rawValue,
        displayName: "Snack",
        displayPrice: "$4.99",
        price: Decimal(499) / 100
    )
    static let lunch = TipProduct.fixture(
        id: TipJarCatalog.Tip.lunch.rawValue,
        displayName: "Lunch",
        displayPrice: "$9.99",
        price: Decimal(999) / 100
    )
}
