import Foundation

// MARK: - Models

struct iTunesStorefrontInfo: Equatable {
    let country: String
    let averageRating: Double?
    let ratingCount: Int?
}

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

    // App Store rating (aggregated from iTunes Lookup across all storefronts)
    var storeAverageRating: Double?
    var storeRatingCount: Int?
    var storefronts: [iTunesStorefrontInfo] = []

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

    /// Total ratings across every storefront (matches what is shown on the App Store).
    var totalRatingCount: Int {
        storeRatingCount ?? 0
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
        Task {
            await load()
        }
    }

    func load() async {
        uiState.isLoading = true
        uiState.error = nil
        uiState.reviews = []
        lastPageResponse = nil

        // Fetch App Store rating and reviews in parallel
        async let ratingTask: () = fetchAppStoreRating()
        async let reviewsTask: () = fetchFirstPage()

        _ = await (ratingTask, reviewsTask)

        uiState.isLoading = false
    }

    /// Aggregates iTunes Lookup data across every storefront where the app is available.
    /// `averageRating` is a count-weighted mean and `ratingCount` is the global sum,
    /// matching what users see on the App Store.
    private func fetchAppStoreRating() async {
        let storefronts = await iTunesLookupAvailableStorefronts(bundleId: uiState.bundleId)
        uiState.storefronts = storefronts

        let totalCount = storefronts.reduce(0) { $0 + ($1.ratingCount ?? 0) }
        guard totalCount > 0 else {
            uiState.storeAverageRating = nil
            uiState.storeRatingCount = 0
            Log.print.info("[RatingsReviews] iTunes storefronts: \(storefronts.count) found, no ratings yet")
            return
        }

        let weightedSum = storefronts.reduce(0.0) { acc, info in
            guard let avg = info.averageRating, let count = info.ratingCount else { return acc }
            return acc + avg * Double(count)
        }
        let weightedAverage = weightedSum / Double(totalCount)

        uiState.storeAverageRating = weightedAverage
        uiState.storeRatingCount = totalCount
        Log.print.info("[RatingsReviews] iTunes aggregate across \(storefronts.count) storefronts: avg \(weightedAverage), count \(totalCount)")
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

    // MARK: - iTunes Storefront Availability

    /// All App Store storefront codes (ISO 3166-1 alpha-2, lowercase).
    /// Source: https://en.wikipedia.org/wiki/App_Store_(Apple)#Distribution
    private static let appStoreStorefronts: [String] = [
        "ae", "ag", "ai", "al", "am", "ao", "ar", "at", "au", "az",
        "bb", "be", "bf", "bg", "bh", "bj", "bm", "bn", "bo", "br",
        "bs", "bt", "bw", "by", "bz", "ca", "cd", "cg", "ch", "ci",
        "cl", "cm", "cn", "co", "cr", "cv", "cy", "cz", "de", "dk",
        "dm", "do", "dz", "ec", "ee", "eg", "es", "fi", "fj", "fm",
        "fr", "ga", "gb", "gd", "gh", "gm", "gr", "gt", "gw", "gy",
        "hk", "hn", "hr", "hu", "id", "ie", "il", "in", "iq", "is",
        "it", "jm", "jo", "jp", "ke", "kg", "kh", "kn", "kr", "kw",
        "ky", "kz", "la", "lb", "lc", "lk", "lr", "lt", "lu", "lv",
        "ly", "ma", "md", "me", "mg", "mk", "ml", "mm", "mn", "mo",
        "mr", "ms", "mt", "mu", "mv", "mw", "mx", "my", "mz", "na",
        "ne", "ng", "ni", "nl", "no", "np", "nz", "om", "pa", "pe",
        "pg", "ph", "pk", "pl", "pt", "pw", "py", "qa", "ro", "rs",
        "ru", "rw", "sa", "sb", "sc", "se", "sg", "si", "sk", "sl",
        "sn", "sr", "st", "sv", "sz", "tc", "td", "th", "tj", "tm",
        "tn", "tr", "tt", "tw", "tz", "ua", "ug", "us", "uy", "uz",
        "vc", "ve", "vg", "vn", "vu", "ye", "za", "zm", "zw"
    ]

    /// Probes every App Store storefront via iTunes Lookup and returns the ones where the app
    /// is available. Calls run concurrently with a bounded TaskGroup so the whole sweep
    /// finishes in a few seconds.
    private func iTunesLookupAvailableStorefronts(bundleId: String) async -> [iTunesStorefrontInfo] {
        struct LookupResponse: Decodable {
            let resultCount: Int?
            let results: [LookupApp]?
        }
        struct LookupApp: Decodable {
            let averageUserRating: Double?
            let userRatingCount: Int?
        }

        return await withTaskGroup(of: iTunesStorefrontInfo?.self) { group in
            for country in Self.appStoreStorefronts {
                group.addTask {
                    let urlString = "https://itunes.apple.com/lookup?bundleId=\(bundleId)&country=\(country)"
                    guard let url = URL(string: urlString) else { return nil }
                    guard let (data, _) = try? await URLSession.shared.data(from: url) else { return nil }
                    guard let response = try? JSONDecoder().decode(LookupResponse.self, from: data) else { return nil }
                    guard let app = response.results?.first else { return nil }
                    return iTunesStorefrontInfo(
                        country: country,
                        averageRating: app.averageUserRating,
                        ratingCount: app.userRatingCount
                    )
                }
            }

            var results: [iTunesStorefrontInfo] = []
            for await info in group {
                if let info { results.append(info) }
            }
            return results
                .filter { ($0.averageRating ?? .zero) > .zero }
                .sorted { $0.country < $1.country }
        }
    }
}
