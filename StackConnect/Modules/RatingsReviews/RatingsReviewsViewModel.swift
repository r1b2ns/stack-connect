import Foundation

// MARK: - Protocol

@MainActor
protocol RatingsReviewsViewModelProtocol: ObservableObject {
    var uiState: RatingsReviewsUiState { get set }
    func load() async
    func loadMore() async
    func applyFilter(rating: Int?) async
    func reply(to review: CustomerReviewModel, body: String) async
    func deleteResponse(for review: CustomerReviewModel) async
}

// MARK: - UiState

struct RatingsReviewsUiState {
    var appId: String
    var bundleId: String
    var account: AccountModel
    var reviews: [CustomerReviewModel] = []
    var isLoading = false
    var isLoadingMore = false
    var hasMorePages = false
    var isSending = false
    var toastMessage: ToastMessage?
    var error: String?

    // App Store rating (from iTunes Lookup API)
    var storeAverageRating: Double?
    var storeRatingCount: Int?

    // Rating distribution (from API: meta.paging.total per star)
    var storeRatingDistribution: [Int: Int]?

    // Filters
    var sortOption: ReviewSortOption = .newest
    var filterRating: Int? = nil

    // Reply sheet
    var replyingTo: CustomerReviewModel?
    var replyText: String = ""

    // Detail
    var selectedReview: CustomerReviewModel?

    /// Average rating from the App Store (iTunes Lookup API).
    var averageRating: Double {
        if let store = storeAverageRating { return store }
        return 0
    }

    var ratingCountLabel: String {
        let count = totalRatingCount
        guard count > 0 else { return "" }
        return "\(count.formatted()) \(String(localized: "ratings"))"
    }

    /// Rating distribution from API (exact counts per star), or fallback from loaded reviews.
    var ratingDistribution: [Int: Int] {
        if let store = storeRatingDistribution { return store }
        var dist: [Int: Int] = [1: 0, 2: 0, 3: 0, 4: 0, 5: 0]
        for review in reviews {
            dist[review.rating, default: 0] += 1
        }
        return dist
    }

    var totalRatingCount: Int {
        if let dist = storeRatingDistribution {
            return dist.values.reduce(0, +)
        }
        return ratingDistribution.values.reduce(0, +)
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
    private var lastPageResponse: Any?

    init(
        appId: String,
        bundleId: String,
        account: AccountModel,
        keychain: KeyStorable = KeychainStorable.shared
    ) {
        self.uiState = RatingsReviewsUiState(appId: appId, bundleId: bundleId, account: account)
        self.keychain = keychain
    }

    func load() async {
        uiState.isLoading = true
        uiState.error = nil
        uiState.reviews = []
        lastPageResponse = nil

        // Fetch App Store rating, distribution, and reviews in parallel
        async let ratingTask: () = fetchAppStoreRating()
        async let distributionTask: () = fetchRatingDistribution()
        async let reviewsTask: () = fetchFirstPage()

        _ = await (ratingTask, distributionTask, reviewsTask)

        uiState.isLoading = false
    }

    private func fetchAppStoreRating() async {
        do {
            let lookup = try await iTunesLookup(bundleId: uiState.bundleId)
            uiState.storeAverageRating = lookup.averageRating
            uiState.storeRatingCount = lookup.ratingCount
            Log.print.info("[RatingsReviews] iTunes rating: \(lookup.averageRating ?? 0), count: \(lookup.ratingCount ?? 0)")
        } catch {
            Log.print.error("[RatingsReviews] iTunes lookup failed: \(error.localizedDescription)")
        }
    }

    private func fetchRatingDistribution() async {
        do {
            guard let connection = createConnection() else { return }
            let dist = try await connection.fetchRatingDistribution(appId: uiState.appId)
            uiState.storeRatingDistribution = dist
            Log.print.info("[RatingsReviews] Distribution: \(dist)")
        } catch {
            Log.print.error("[RatingsReviews] Distribution fetch failed: \(error.localizedDescription)")
        }
    }

    private func fetchFirstPage() async {
        do {
            guard let connection = createConnection() else { return }

            let filterRating = uiState.filterRating.map { [String($0)] }

            let page = try await connection.fetchCustomerReviewsPage(
                appId: uiState.appId,
                sort: uiState.sortOption.rawValue,
                filterRating: filterRating,
                limit: 50,
                pageAfterResponse: nil
            )

            uiState.reviews = page.reviews
            uiState.hasMorePages = page.hasNextPage
            lastPageResponse = page.rawResponse

            Log.print.info("[RatingsReviews] Loaded \(page.reviews.count) reviews, hasMore: \(page.hasNextPage), filter: \(self.uiState.filterRating?.description ?? "all")")
        } catch {
            uiState.error = error.localizedDescription
            Log.print.error("[RatingsReviews] Failed to load: \(error.localizedDescription)")
        }
    }

    func applyFilter(rating: Int?) async {
        uiState.filterRating = rating
        uiState.reviews = []
        uiState.isLoading = true
        lastPageResponse = nil

        await fetchFirstPage()

        uiState.isLoading = false
    }

    func loadMore() async {
        guard uiState.hasMorePages, !uiState.isLoadingMore, lastPageResponse != nil else { return }
        uiState.isLoadingMore = true

        do {
            guard let connection = createConnection() else {
                uiState.isLoadingMore = false
                return
            }

            let filterRating = uiState.filterRating.map { [String($0)] }

            let page = try await connection.fetchCustomerReviewsPage(
                appId: uiState.appId,
                sort: uiState.sortOption.rawValue,
                filterRating: filterRating,
                limit: 50,
                pageAfterResponse: lastPageResponse
            )

            uiState.reviews.append(contentsOf: page.reviews)
            uiState.hasMorePages = page.hasNextPage
            lastPageResponse = page.rawResponse

            Log.print.info("[RatingsReviews] Loaded \(page.reviews.count) more reviews, total: \(self.uiState.reviews.count)")
        } catch {
            Log.print.error("[RatingsReviews] Failed to load more: \(error.localizedDescription)")
        }

        uiState.isLoadingMore = false
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

    // MARK: - iTunes Lookup API

    private struct iTunesLookupResult {
        var averageRating: Double?
        var ratingCount: Int?
    }

    private func iTunesLookup(bundleId: String) async throws -> iTunesLookupResult {
        let urlString = "https://itunes.apple.com/lookup?bundleId=\(bundleId)"
        guard let url = URL(string: urlString) else {
            return iTunesLookupResult()
        }

        let (data, _) = try await URLSession.shared.data(from: url)

        struct LookupResponse: Decodable {
            let resultCount: Int?
            let results: [LookupApp]?
        }

        struct LookupApp: Decodable {
            let averageUserRating: Double?
            let userRatingCount: Int?
            let averageUserRatingForCurrentVersion: Double?
            let userRatingCountForCurrentVersion: Int?
        }

        let response = try JSONDecoder().decode(LookupResponse.self, from: data)
        guard let app = response.results?.first else {
            return iTunesLookupResult()
        }

        return iTunesLookupResult(
            averageRating: app.averageUserRating,
            ratingCount: app.userRatingCount
        )
    }
}
