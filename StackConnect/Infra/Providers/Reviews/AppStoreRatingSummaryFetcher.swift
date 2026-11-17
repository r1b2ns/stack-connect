import Foundation

/// One App Store storefront where the app is listed, with its rating there.
struct iTunesStorefrontInfo: Equatable, Sendable {
    let country: String
    let averageRating: Double?
    let ratingCount: Int?
}

/// An app's App Store rating across every storefront (what the App Store shows).
struct AppStoreRatingSummary: Equatable, Sendable {
    /// Storefronts where the app has ratings, sorted by country code.
    let storefronts: [iTunesStorefrontInfo]
    /// False when some storefront couldn't be asked (network or decoding
    /// failure): the numbers may then undercount.
    let isComplete: Bool

    /// Total ratings across every storefront.
    var ratingCount: Int {
        storefronts.reduce(0) { $0 + ($1.ratingCount ?? 0) }
    }

    /// Count-weighted mean across storefronts; `nil` while there are no ratings.
    var averageRating: Double? {
        let count = ratingCount
        guard count > 0 else { return nil }
        let weightedSum = storefronts.reduce(0.0) { sum, info in
            guard let average = info.averageRating, let ratings = info.ratingCount else { return sum }
            return sum + average * Double(ratings)
        }
        return weightedSum / Double(count)
    }
}

/// Fetches the App Store rating summary shown above an app's reviews.
protocol AppStoreRatingSummaryFetching: Sendable {
    /// `nil` when the fetch was cancelled before it finished: a partial sweep
    /// would undercount, so callers keep whatever they already show.
    func fetchSummary(bundleId: String) async -> AppStoreRatingSummary?
}

/// Rating summary from the public iTunes Lookup API, asking every App Store
/// storefront concurrently (one request per storefront, a few seconds overall).
struct ITunesRatingSummaryFetcher: AppStoreRatingSummaryFetching {

    typealias DataLoader = @Sendable (URL) async throws -> Data

    /// All App Store storefront codes (ISO 3166-1 alpha-2, lowercase).
    /// Source: https://en.wikipedia.org/wiki/App_Store_(Apple)#Distribution
    static let appStoreStorefronts: [String] = [
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

    let storefronts: [String]
    private let loadData: DataLoader

    /// - Parameters:
    ///   - storefronts: storefront codes to ask (all of them by default).
    ///   - loadData: GET for one lookup URL; `URLSession.shared` by default.
    init(
        storefronts: [String] = Self.appStoreStorefronts,
        loadData: @escaping DataLoader = { try await URLSession.shared.data(from: $0).0 }
    ) {
        self.storefronts = storefronts
        self.loadData = loadData
    }

    func fetchSummary(bundleId: String) async -> AppStoreRatingSummary? {
        let countries = storefronts
        let results = await withTaskGroup(of: StorefrontLookup.self) { group in
            for country in countries {
                group.addTask { await lookup(bundleId: bundleId, country: country) }
            }
            var results: [StorefrontLookup] = []
            for await result in group {
                results.append(result)
            }
            return results
        }

        // Cancelled (e.g. the screen went away): requests failed or never ran,
        // so the result is partial by construction — never report it.
        guard !Task.isCancelled else { return nil }

        var rated: [iTunesStorefrontInfo] = []
        var isComplete = true
        for result in results {
            switch result {
            case .listed(let info):
                if (info.averageRating ?? .zero) > .zero {
                    rated.append(info)
                }
            case .notListed:
                break
            case .failed:
                isComplete = false
            }
        }
        return AppStoreRatingSummary(
            storefronts: rated.sorted { $0.country < $1.country },
            isComplete: isComplete
        )
    }

    // MARK: - Private

    private enum StorefrontLookup: Sendable {
        case listed(iTunesStorefrontInfo)
        /// The storefront answered: the app isn't sold there.
        case notListed
        /// No usable answer (network or decoding failure).
        case failed
    }

    private struct LookupResponse: Decodable {
        let results: [LookupApp]?
    }

    private struct LookupApp: Decodable {
        let averageUserRating: Double?
        let userRatingCount: Int?
    }

    private func lookup(bundleId: String, country: String) async -> StorefrontLookup {
        var components = URLComponents(string: "https://itunes.apple.com/lookup")
        components?.queryItems = [
            URLQueryItem(name: "bundleId", value: bundleId),
            URLQueryItem(name: "country", value: country)
        ]
        guard let url = components?.url,
              let data = try? await loadData(url),
              let response = try? JSONDecoder().decode(LookupResponse.self, from: data) else {
            return .failed
        }
        guard let app = response.results?.first else {
            return .notListed
        }
        return .listed(iTunesStorefrontInfo(
            country: country,
            averageRating: app.averageUserRating,
            ratingCount: app.userRatingCount
        ))
    }
}
