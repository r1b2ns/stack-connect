import Foundation
import StoreKit

// MARK: - Protocol

/// Loads and buys tips. Keeps StoreKit behind a seam so the tip jar's
/// ViewModel is unit tested with a mock.
protocol TipJarServiceProtocol: Sendable {
    /// The tips on sale, cheapest first. Empty when none is available in the
    /// current storefront; throws when the App Store can't be reached.
    func loadProducts() async throws -> [TipProduct]

    /// Buys the tip `productID`. Never throws: every StoreKit result and error
    /// is mapped to a `TipPurchaseOutcome`.
    func purchase(productID: String) async -> TipPurchaseOutcome
}

// MARK: - StoreKit 2 implementation

actor StoreKitTipJarService: TipJarServiceProtocol {

    private let productIDs: [String]
    /// Products from the last load, reused by `purchase` to avoid a round trip.
    private var productsByID: [String: Product] = [:]

    init(productIDs: [String] = TipJarCatalog.productIDs) {
        self.productIDs = productIDs
    }

    func loadProducts() async throws -> [TipProduct] {
        let products = try await Product.products(for: productIDs)
        productsByID = Dictionary(products.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        Log.print.info("[TipJar] Loaded \(products.count) of \(self.productIDs.count) products")
        return TipProduct.sortedByPrice(products.map(TipProduct.init(product:)))
    }

    func purchase(productID: String) async -> TipPurchaseOutcome {
        do {
            guard let product = try await product(for: productID) else {
                Log.print.error("[TipJar] Product \(productID, privacy: .public) is not available")
                return .failed(.productUnavailable)
            }
            let result = try await product.purchase()
            let outcome = await resolve(result)
            Log.print.info("[TipJar] Purchase of \(productID, privacy: .public) ended: \(String(describing: outcome), privacy: .public)")
            return outcome
        } catch {
            Log.print.error("[TipJar] Purchase of \(productID, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            return TipPurchaseOutcomeMapper.outcome(for: error)
        }
    }

    // MARK: - Private

    private func product(for productID: String) async throws -> Product? {
        if let cached = productsByID[productID] { return cached }
        let product = try await Product.products(for: [productID]).first
        productsByID[productID] = product
        return product
    }

    /// Finishes verified transactions only. An unverified one stays
    /// unfinished, so StoreKit can deliver it again for a later check.
    private func resolve(_ result: Product.PurchaseResult) async -> TipPurchaseOutcome {
        switch result {
        case .success(let verification):
            switch verification {
            case .verified(let transaction):
                await transaction.finish()
                return TipPurchaseOutcomeMapper.outcome(for: .verified)
            case .unverified(_, let error):
                Log.print.error("[TipJar] Unverified transaction: \(error.localizedDescription, privacy: .public)")
                return TipPurchaseOutcomeMapper.outcome(for: .unverified)
            }
        case .userCancelled:
            return TipPurchaseOutcomeMapper.outcome(for: .userCancelled)
        case .pending:
            return TipPurchaseOutcomeMapper.outcome(for: .pending)
        @unknown default:
            return TipPurchaseOutcomeMapper.outcome(for: .unknown)
        }
    }
}

// MARK: - Result mapping

/// Pure mapping from StoreKit results and errors to `TipPurchaseOutcome`,
/// split out of the service so it is unit tested without real transactions.
enum TipPurchaseOutcomeMapper {

    /// `Product.PurchaseResult` flattened, without the transaction payload.
    enum StoreResult: Equatable, Sendable {
        case verified
        case unverified
        case userCancelled
        case pending
        case unknown
    }

    static func outcome(for result: StoreResult) -> TipPurchaseOutcome {
        switch result {
        case .verified: return .success
        case .unverified: return .failed(.verificationFailed)
        case .userCancelled: return .userCancelled
        case .pending: return .pending
        case .unknown: return .failed(.unknown)
        }
    }

    static func outcome(for error: Error) -> TipPurchaseOutcome {
        if let storeKitError = error as? StoreKitError {
            switch storeKitError {
            case .userCancelled: return .userCancelled
            case .networkError: return .failed(.network)
            case .notAvailableInStorefront: return .failed(.productUnavailable)
            case .notEntitled: return .failed(.notAllowed)
            default: return .failed(.unknown)
            }
        }
        if let purchaseError = error as? Product.PurchaseError {
            switch purchaseError {
            case .productUnavailable: return .failed(.productUnavailable)
            case .purchaseNotAllowed: return .failed(.notAllowed)
            default: return .failed(.unknown)
            }
        }
        if error is URLError {
            return .failed(.network)
        }
        return .failed(.unknown)
    }
}

// MARK: - Product mapping

private extension TipProduct {
    init(product: Product) {
        self.init(
            id: product.id,
            displayName: product.displayName,
            description: product.description,
            displayPrice: product.displayPrice,
            price: product.price
        )
    }
}
