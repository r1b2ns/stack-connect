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
//#if DEBUG
//    case individualMonthly = "individualMonthId"
//    case individualYearly  = "individualYearlyId"
//    case teamMonthly       = "teamMonthId"
//    case teamYearly        = "teamYearlyId"
//    case lifetime          = "lifetimeId"
//#else
    case individualMonthly = "prdIndividualMonthId"
    case individualYearly  = "prdIndividualYearlyId"
    case teamMonthly       = "prdTeamMonthId"
    case teamYearly        = "prdTeamYearlyId"
    case lifetime          = "prdLifetimeId"
//#endif

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

    private static let importedAccessKey = "subscription.hasImportedAccess"

    @Published var currentTier: SubscriptionTier?
    @Published var products: [Product] = []
    @Published var isLoading = false
    @Published var purchaseError: String?
    @Published var loadError: String?
    @Published var hasImportedAccess: Bool

    /// User has access via subscription OR imported account
    var isSubscribed: Bool {
        currentTier != nil || hasImportedAccess
    }

    private var transactionListener: Task<Void, Never>?

    init() {
        self.hasImportedAccess = UserDefaults.standard.bool(forKey: Self.importedAccessKey)
        transactionListener = listenForTransactions()
    }

    func grantImportedAccess() {
        hasImportedAccess = true
        UserDefaults.standard.set(true, forKey: Self.importedAccessKey)
        Log.print.info("[Subscription] Granted imported access")
    }

    func revokeImportedAccess() {
        hasImportedAccess = false
        UserDefaults.standard.set(false, forKey: Self.importedAccessKey)
    }

    deinit {
        transactionListener?.cancel()
    }

    // MARK: - Load Products

    func loadProducts() async {
        isLoading = true
        loadError = nil

        let requestedIDs = SubscriptionProductID.allIDs
        let maxAttempts = 3
        var lastError: Error?

        for attempt in 1...maxAttempts {
            Log.print.info("[Subscription] Loading products (attempt \(attempt, privacy: .public)/\(maxAttempts, privacy: .public)) — requested: \(requestedIDs.joined(separator: ", "), privacy: .public)")

            do {
                let fetched = try await Product.products(for: requestedIDs)
                products = fetched.sorted { $0.price < $1.price }

                let receivedIDs = products.map(\.id)
                Log.print.info("[Subscription] Received \(self.products.count, privacy: .public) products: \(receivedIDs.joined(separator: ", "), privacy: .public)")

                let missing = Array(Set(requestedIDs).subtracting(receivedIDs)).sorted()
                if !missing.isEmpty {
                    Log.print.error("[Subscription] Missing products from App Store Connect: \(missing.joined(separator: ", "), privacy: .public)")
                }

                if products.isEmpty {
                    loadError = String(
                        localized: "Unable to load subscription plans. Please make sure you are connected to the Internet and signed in with a valid App Store account."
                    )
                } else {
                    loadError = nil
                }

                isLoading = false
                return
            } catch {
                lastError = error
                Log.print.error("[Subscription] Attempt \(attempt, privacy: .public) failed: \(String(describing: error), privacy: .public)")

                if attempt < maxAttempts {
                    try? await Task.sleep(nanoseconds: UInt64(attempt) * 1_000_000_000)
                }
            }
        }

        loadError = lastError?.localizedDescription ?? String(localized: "Failed to load subscription plans.")
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
