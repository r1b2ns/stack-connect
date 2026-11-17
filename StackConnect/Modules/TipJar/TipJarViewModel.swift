import Foundation
import StackProtocols

// MARK: - Protocol

@MainActor
protocol TipJarViewModelProtocol: ObservableObject {
    var uiState: TipJarUiState { get set }
    func load() async
    func retry() async
    func purchase(_ tip: TipProduct) async
    func dismissThankYou()
    func dismissError()
}

// MARK: - UiState

struct TipJarUiState {

    enum Phase: Equatable {
        case loading
        case loaded
        /// No tip could be loaded (offline, storefront without the products).
        case unavailable
    }

    var phase: Phase = .loading
    /// Cheapest first.
    var tips: [TipProduct] = []
    /// The tip whose payment sheet is up; every tip button is disabled meanwhile.
    var purchasingProductID: String?
    var isShowingThankYou = false
    /// The last purchase is waiting for approval (Ask to Buy).
    var isPending = false
    /// Non-nil while the purchase-failure alert is shown.
    var errorMessage: String?

    var isPurchasing: Bool { purchasingProductID != nil }
}

// MARK: - Implementation

@MainActor
final class TipJarViewModel: TipJarViewModelProtocol {

    @Published var uiState = TipJarUiState()

    private let service: TipJarServiceProtocol
    private let analytics: AnalyticsTracking
    private let tipRecorder: TipJarTipRecording

    /// - Parameter tipRecorder: Told about every completed tip, so the Home
    ///   "support the project" card never shows again.
    init(
        service: TipJarServiceProtocol = StoreKitTipJarService(),
        analytics: AnalyticsTracking = AnalyticsService.shared,
        tipRecorder: TipJarTipRecording = TipJarPromptService.shared
    ) {
        self.service = service
        self.analytics = analytics
        self.tipRecorder = tipRecorder
    }

    /// Loads the tips. The spinner only shows while nothing is on screen, so a
    /// reload on re-appear keeps the list visible.
    func load() async {
        if uiState.tips.isEmpty {
            uiState.phase = .loading
        }

        do {
            let products = try await service.loadProducts()
            uiState.tips = TipProduct.sortedByPrice(products)
        } catch {
            Log.print.error("[TipJar] Failed to load products: \(error.localizedDescription, privacy: .public)")
        }
        uiState.phase = uiState.tips.isEmpty ? .unavailable : .loaded
    }

    func retry() async {
        analytics.track(.buttonTap(.tryAgain, on: .tipJar))
        await load()
    }

    func purchase(_ tip: TipProduct) async {
        guard !uiState.isPurchasing else { return }
        analytics.track(.buttonTap(.purchaseTip, on: .tipJar))

        uiState.purchasingProductID = tip.id
        uiState.isPending = false
        defer { uiState.purchasingProductID = nil }

        let outcome = await service.purchase(productID: tip.id)
        switch outcome {
        case .success:
            uiState.isShowingThankYou = true
            tipRecorder.recordCompletedTip()
            track(tip, result: .success)
        case .userCancelled:
            track(tip, result: .cancelled)
        case .pending:
            uiState.isPending = true
            track(tip, result: .pending)
        case .failed(let failure):
            uiState.errorMessage = Self.message(for: failure)
            track(tip, result: .failure)
        }
    }

    func dismissThankYou() {
        uiState.isShowingThankYou = false
    }

    func dismissError() {
        uiState.errorMessage = nil
    }

    // MARK: - Private

    private func track(_ tip: TipProduct, result: AnalyticsResult) {
        analytics.track(.action(
            .purchaseTip,
            on: .tipJar,
            result: result,
            parameters: [AnalyticsParameterKey.productId: .string(tip.id)]
        ))
    }

    static func message(for failure: TipPurchaseFailure) -> String {
        switch failure {
        case .productUnavailable:
            return String(localized: "This tip isn't available right now. Please try again later.")
        case .notAllowed:
            return String(localized: "Purchases aren't allowed on this device.")
        case .network:
            return String(localized: "Couldn't reach the App Store. Check your connection and try again.")
        case .verificationFailed:
            return String(localized: "The App Store couldn't verify this purchase.")
        case .unknown:
            return String(localized: "The purchase couldn't be completed. Please try again.")
        }
    }
}
