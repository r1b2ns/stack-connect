import Foundation

// MARK: - Protocol

@MainActor
protocol RatingsReviewsViewModelProtocol: ObservableObject {
    var uiState: RatingsReviewsUiState { get set }
    func load() async
    func reply(to review: CustomerReviewModel, body: String) async
    func deleteResponse(for review: CustomerReviewModel) async
}

// MARK: - UiState

struct RatingsReviewsUiState {
    var appId: String
    var account: AccountModel
    var reviews: [CustomerReviewModel] = []
    var isLoading = false
    var isSending = false
    var toastMessage: ToastMessage?
    var error: String?

    // Filters
    var sortOption: ReviewSortOption = .newest
    var filterRating: Int? = nil

    // Reply sheet
    var replyingTo: CustomerReviewModel?
    var replyText: String = ""

    // Detail
    var selectedReview: CustomerReviewModel?

    var filteredReviews: [CustomerReviewModel] {
        guard let rating = filterRating else { return reviews }
        return reviews.filter { $0.rating == rating }
    }

    var averageRating: Double {
        guard !reviews.isEmpty else { return 0 }
        let sum = reviews.reduce(0) { $0 + $1.rating }
        return Double(sum) / Double(reviews.count)
    }

    var ratingDistribution: [Int: Int] {
        var dist: [Int: Int] = [1: 0, 2: 0, 3: 0, 4: 0, 5: 0]
        for review in reviews {
            dist[review.rating, default: 0] += 1
        }
        return dist
    }
}

enum ReviewSortOption: String, CaseIterable, Identifiable {
    case newest = "-createdDate"
    case oldest = "createdDate"
    case highestRating = "-rating"
    case lowestRating = "rating"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .newest:        return String(localized: "Newest")
        case .oldest:        return String(localized: "Oldest")
        case .highestRating: return String(localized: "Highest Rating")
        case .lowestRating:  return String(localized: "Lowest Rating")
        }
    }
}

// MARK: - Implementation

@MainActor
final class RatingsReviewsViewModel: RatingsReviewsViewModelProtocol {

    @Published var uiState: RatingsReviewsUiState

    private let keychain: KeyStorable

    init(
        appId: String,
        account: AccountModel,
        keychain: KeyStorable = KeychainStorable.shared
    ) {
        self.uiState = RatingsReviewsUiState(appId: appId, account: account)
        self.keychain = keychain
    }

    func load() async {
        uiState.isLoading = true
        uiState.error = nil

        do {
            guard let connection = createConnection() else {
                uiState.isLoading = false
                return
            }

            uiState.reviews = try await connection.fetchCustomerReviews(
                appId: uiState.appId,
                sort: uiState.sortOption.rawValue,
                limit: 200
            )

            Log.print.info("[RatingsReviews] Loaded \(self.uiState.reviews.count) reviews")
        } catch {
            uiState.error = error.localizedDescription
            Log.print.error("[RatingsReviews] Failed to load: \(error.localizedDescription)")
        }

        uiState.isLoading = false
    }

    func reply(to review: CustomerReviewModel, body: String) async {
        uiState.isSending = true

        do {
            guard let connection = createConnection() else {
                uiState.isSending = false
                return
            }

            try await connection.replyToReview(reviewId: review.id, responseBody: body)

            if let idx = uiState.reviews.firstIndex(where: { $0.id == review.id }) {
                uiState.reviews[idx].responseBody = body
                uiState.reviews[idx].responseState = "PENDING_PUBLISH"
                uiState.reviews[idx].responseDate = Date()
            }

            uiState.replyingTo = nil
            uiState.replyText = ""
            uiState.toastMessage = ToastMessage(String(localized: "Reply sent"), icon: "paperplane.fill")
            Log.print.info("[RatingsReviews] Replied to review \(review.id)")
        } catch {
            uiState.toastMessage = ToastMessage(String(localized: "Failed to send reply"), icon: "exclamationmark.triangle.fill")
            Log.print.error("[RatingsReviews] Reply failed: \(error.localizedDescription)")
        }

        uiState.isSending = false
    }

    func deleteResponse(for review: CustomerReviewModel) async {
        guard let responseId = review.responseId else { return }

        do {
            guard let connection = createConnection() else { return }
            try await connection.deleteReviewResponse(responseId: responseId)

            if let idx = uiState.reviews.firstIndex(where: { $0.id == review.id }) {
                uiState.reviews[idx].responseId = nil
                uiState.reviews[idx].responseBody = nil
                uiState.reviews[idx].responseState = nil
                uiState.reviews[idx].responseDate = nil
            }

            uiState.toastMessage = ToastMessage(String(localized: "Reply deleted"), icon: "trash")
            Log.print.info("[RatingsReviews] Deleted response for review \(review.id)")
        } catch {
            uiState.toastMessage = ToastMessage(String(localized: "Failed to delete reply"), icon: "exclamationmark.triangle.fill")
            Log.print.error("[RatingsReviews] Delete response failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Private

    private func createConnection() -> AppleAccountConnection? {
        guard let credentials: AppleCredentials = keychain.object(forKey: "credentials.\(uiState.account.id)") else {
            return nil
        }
        return AppleAccountConnection(credentials: credentials)
    }
}
