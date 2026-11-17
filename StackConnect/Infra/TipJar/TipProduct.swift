import Foundation

/// A tip on sale, decoupled from StoreKit's `Product` so ViewModels and tests
/// never need real App Store values.
struct TipProduct: Identifiable, Hashable, Sendable {
    let id: String
    let displayName: String
    let description: String
    /// Localized, storefront-formatted price (e.g. "US$ 0.99").
    let displayPrice: String
    /// Numeric price, used only for ordering.
    let price: Decimal

    var emoji: String { TipJarCatalog.emoji(for: id) }

    /// Cheapest first; ties keep a stable order by product ID.
    static func sortedByPrice(_ products: [TipProduct]) -> [TipProduct] {
        products.sorted { lhs, rhs in
            lhs.price == rhs.price ? lhs.id < rhs.id : lhs.price < rhs.price
        }
    }
}

/// What happened to a tip purchase, in the app's own terms.
enum TipPurchaseOutcome: Equatable, Sendable {
    /// Verified and finished: the tip went through.
    case success
    /// The user dismissed the payment sheet. Not an error.
    case userCancelled
    /// Waiting for approval (Ask to Buy, SCA). It completes later through
    /// `Transaction.updates`, which `TipJarTransactionObserver` finishes.
    case pending
    case failed(TipPurchaseFailure)
}

enum TipPurchaseFailure: Equatable, Sendable {
    /// The product isn't on sale (not loaded, not in this storefront).
    case productUnavailable
    /// The device or account can't make purchases (Screen Time, MDM).
    case notAllowed
    /// The App Store couldn't be reached.
    case network
    /// The App Store returned a transaction that failed JWS verification. It is
    /// left unfinished on purpose.
    case verificationFailed
    case unknown
}
