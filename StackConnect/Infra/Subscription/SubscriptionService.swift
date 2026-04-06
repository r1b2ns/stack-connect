import Foundation
import StoreKit

// MARK: - Subscription Tier

enum SubscriptionTier: String, Codable {
    case individual
    case team
    case lifetime

    var displayName: String {
        switch self {
        case .individual: return String(localized: "Individual")
        case .team:       return String(localized: "Team")
        case .lifetime:   return String(localized: "Lifetime")
        }
    }

    var canExport: Bool {
        self != .individual
    }
}

// MARK: - Product IDs

enum SubscriptionProductID: String, CaseIterable {
#if DEBUG
    case individualMonthly = "individualMonthId"
    case individualYearly  = "individualYearlyId"
    case teamMonthly       = "teamMonthId"
    case teamYearly        = "teamYearlyId"
    case lifetime          = "lifetimeId"
#else
    case individualMonthly = "prdIndividualMonthId"
    case individualYearly  = "prdIndividualYearlyId"
    case teamMonthly       = "prdTeamMonthId"
    case teamYearly        = "prdTeamYearlyId"
    case lifetime          = "prdLifetimeId"
#endif

    var tier: SubscriptionTier {
        switch self {
        case .individualMonthly, .individualYearly: return .individual
        case .teamMonthly, .teamYearly:             return .team
        case .lifetime:                              return .lifetime
        }
    }

    static var allIDs: [String] {
        allCases.map(\.rawValue)
    }
}

// MARK: - Billing Period

enum BillingPeriod: String, CaseIterable {
    case monthly
    case yearly

    var displayName: String {
        switch self {
        case .monthly: return String(localized: "Monthly")
        case .yearly:  return String(localized: "Yearly")
        }
    }
}

// MARK: - Subscription Service

@MainActor
final class SubscriptionService: ObservableObject {

    @Published var currentTier: SubscriptionTier?
    @Published var products: [Product] = []
    @Published var isLoading = false
    @Published var purchaseError: String?

    var isSubscribed: Bool {
        currentTier != nil
    }

    private var transactionListener: Task<Void, Never>?

    init() {
        transactionListener = listenForTransactions()
    }

    deinit {
        transactionListener?.cancel()
    }

    // MARK: - Load Products

    func loadProducts() async {
        isLoading = true
        do {
            products = try await Product.products(for: SubscriptionProductID.allIDs)
                .sorted { $0.price < $1.price }
            Log.print.info("[Subscription] Loaded \(self.products.count) products")
        } catch {
            Log.print.error("[Subscription] Failed to load products: \(error.localizedDescription)")
        }
        isLoading = false
    }

    // MARK: - Purchase

    func purchase(_ product: Product) async -> Bool {
        purchaseError = nil
        do {
            let result = try await product.purchase()

            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await transaction.finish()
                await checkEntitlements()
                Log.print.info("[Subscription] Purchased: \(product.id)")
                return true

            case .userCancelled:
                Log.print.info("[Subscription] User cancelled purchase")
                return false

            case .pending:
                Log.print.info("[Subscription] Purchase pending")
                return false

            @unknown default:
                return false
            }
        } catch {
            purchaseError = error.localizedDescription
            Log.print.error("[Subscription] Purchase failed: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Restore

    func restorePurchases() async {
        isLoading = true
        try? await AppStore.sync()
        await checkEntitlements()
        isLoading = false
        Log.print.info("[Subscription] Restore completed. Tier: \(String(describing: self.currentTier))")
    }

    // MARK: - Check Entitlements

    func checkEntitlements() async {
        var foundTier: SubscriptionTier?

        for await result in Transaction.currentEntitlements {
            guard let transaction = try? checkVerified(result) else { continue }

            if let productID = SubscriptionProductID(rawValue: transaction.productID) {
                // Lifetime takes priority
                if productID.tier == .lifetime {
                    foundTier = .lifetime
                    break
                }
                // Team > Individual
                if foundTier == nil || productID.tier == .team {
                    foundTier = productID.tier
                }
            }
        }

        currentTier = foundTier
        Log.print.info("[Subscription] Current tier: \(String(describing: self.currentTier))")
    }

    // MARK: - Product Helpers

    func product(for id: SubscriptionProductID) -> Product? {
        products.first { $0.id == id.rawValue }
    }

    func individualProduct(period: BillingPeriod) -> Product? {
        switch period {
        case .monthly: return product(for: .individualMonthly)
        case .yearly:  return product(for: .individualYearly)
        }
    }

    func teamProduct(period: BillingPeriod) -> Product? {
        switch period {
        case .monthly: return product(for: .teamMonthly)
        case .yearly:  return product(for: .teamYearly)
        }
    }

    var lifetimeProduct: Product? {
        product(for: .lifetime)
    }

    // MARK: - Private

    private func listenForTransactions() -> Task<Void, Never> {
        Task.detached { [weak self] in
            for await result in Transaction.updates {
                guard let self else { return }
                if let transaction = try? self.checkVerified(result) {
                    await transaction.finish()
                    await self.checkEntitlements()
                }
            }
        }
    }

    private nonisolated func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified(_, let error):
            throw error
        case .verified(let value):
            return value
        }
    }
}
