import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import StackProtocols

#if canImport(os)
import os
#endif

// T-W15 — iTunes Lookup Service for the Windows GUI.
//
// Foundation-pure service that queries the iTunes Lookup API across all
// ~175 App Store storefronts concurrently, aggregates per-storefront
// rating data into a single `AggregateRating`, and caches results via
// `PersistentStorable` with a configurable TTL.
//
// Mirrors the proven iOS `RatingsReviewsViewModel.iTunesLookupAvailableStorefronts`
// approach but extracted into a standalone, testable service with:
// - Protocol-based networking (`ITunesLookupNetworking`) for test injection
// - Pure `computeWeightedAverage` function (TC-079)
// - SQLite TTL cache (stale-while-revalidate)
// - Graceful failure (returns nil, never crashes)

// MARK: - Aggregate Rating Model

/// The result of aggregating iTunes Lookup data across all storefronts.
/// Carries both the weighted average and total count so downstream consumers
/// (T-W16 `WindowsRatingsReviewsModel`, T-W17 aggregate card) have everything
/// they need.
public struct AggregateRating: Codable, Equatable, Sendable {
    /// Count-weighted average rating across all storefronts (1.0...5.0).
    public let averageRating: Double

    /// Sum of `userRatingCount` across all storefronts.
    public let totalCount: Int

    /// Number of storefronts that reported rating data.
    public let storefrontCount: Int

    /// Per-storefront breakdown (sorted by country code).
    public let storefronts: [StorefrontRating]

    /// Timestamp when this aggregate was computed (used for TTL).
    public let fetchedAt: Date

    public init(
        averageRating: Double,
        totalCount: Int,
        storefrontCount: Int,
        storefronts: [StorefrontRating],
        fetchedAt: Date = Date()
    ) {
        self.averageRating = averageRating
        self.totalCount = totalCount
        self.storefrontCount = storefrontCount
        self.storefronts = storefronts
        self.fetchedAt = fetchedAt
    }
}

/// Per-storefront rating info returned by the iTunes Lookup API.
public struct StorefrontRating: Codable, Equatable, Sendable {
    /// ISO 3166-1 alpha-2 country code (lowercase).
    public let country: String

    /// Average user rating for this storefront (all versions).
    public let averageRating: Double

    /// Total number of ratings for this storefront.
    public let ratingCount: Int

    public init(country: String, averageRating: Double, ratingCount: Int) {
        self.country = country
        self.averageRating = averageRating
        self.ratingCount = ratingCount
    }
}

// MARK: - Networking Protocol

/// Abstraction over the HTTP fetch for a single iTunes Lookup request.
/// Injecting this allows unit tests to mock all network calls without
/// hitting the real iTunes API.
public protocol ITunesLookupNetworking: Sendable {
    /// Fetches raw data from the given URL.
    /// - Returns: The response data, or throws on network/HTTP failure.
    func fetchData(from url: URL) async throws -> Data
}

/// Default implementation using `URLSession`.
public struct URLSessionLookupNetworking: ITunesLookupNetworking {
    public init() {}

    public func fetchData(from url: URL) async throws -> Data {
        let (data, _) = try await URLSession.shared.data(from: url)
        return data
    }
}

// MARK: - Error

/// Errors specific to the iTunes Lookup service.
public enum ITunesLookupError: Error, Equatable {
    /// Every single storefront request failed (total network failure).
    /// Callers should fall back to cached data or surface "rating unavailable".
    case allStorefrontsFailed
}

// MARK: - iTunes Lookup Service

/// Queries the iTunes Lookup API across all App Store storefronts, aggregates
/// rating data, and caches the result with a configurable TTL.
///
/// Thread-safe: all public methods are `Sendable`-compatible; the service
/// itself holds no mutable state (cache lives in `PersistentStorable`).
public final class ITunesLookupService: Sendable {

    // MARK: - Dependencies

    private let networking: ITunesLookupNetworking
    private let storage: PersistentStorable
    private let cacheTTL: TimeInterval
    private let dateProvider: @Sendable () -> Date

    // MARK: - Init

    /// Creates a new iTunes Lookup service.
    ///
    /// - Parameters:
    ///   - networking: The network layer to use for HTTP requests. Defaults
    ///     to `URLSessionLookupNetworking()`.
    ///   - storage: Persistent storage for the TTL cache. Must be the same
    ///     SQLite-backed `PersistentStorable` used elsewhere in the app.
    ///   - cacheTTL: How long (in seconds) a cached `AggregateRating` is
    ///     considered fresh. Defaults to 1 hour (3600s).
    ///   - dateProvider: Injectable clock for testability. Defaults to `Date()`.
    public init(
        networking: ITunesLookupNetworking = URLSessionLookupNetworking(),
        storage: PersistentStorable,
        cacheTTL: TimeInterval = 3600,
        dateProvider: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.networking = networking
        self.storage = storage
        self.cacheTTL = cacheTTL
        self.dateProvider = dateProvider
    }

    // MARK: - Public API

    /// Fetches the aggregate rating for the given bundle ID, using cache
    /// when fresh and refreshing when stale.
    ///
    /// - Parameter bundleId: The app's bundle identifier.
    /// - Returns: The aggregate rating, or `nil` if the lookup fails entirely
    ///   and no cached data is available (AC-W10-3: graceful failure).
    public func fetchAggregateRating(bundleId: String) async -> AggregateRating? {
        let cacheKey = cacheId(for: bundleId)

        // Phase 1: Check cache
        if let cached = await loadCached(id: cacheKey) {
            let age = dateProvider().timeIntervalSince(cached.fetchedAt)
            if age < cacheTTL {
                #if canImport(os)
                Logger(subsystem: "com.stackconnect.windows", category: "ITunesLookup")
                    .info("[ITunesLookup] Cache hit for \(bundleId, privacy: .public), age: \(Int(age))s")
                #endif
                return cached
            }
            // Stale: attempt refresh, fall back to stale data on failure
            #if canImport(os)
            Logger(subsystem: "com.stackconnect.windows", category: "ITunesLookup")
                .info("[ITunesLookup] Cache stale for \(bundleId, privacy: .public), refreshing")
            #endif
        }

        // Phase 2: Live lookup
        do {
            let result = try await lookupAllStorefronts(bundleId: bundleId)
            // Persist to cache
            await saveToCache(result, id: cacheKey)
            return result
        } catch {
            #if canImport(os)
            Logger(subsystem: "com.stackconnect.windows", category: "ITunesLookup")
                .warning("[ITunesLookup] Lookup failed for \(bundleId, privacy: .public): \(error.localizedDescription, privacy: .public)")
            #endif
            // Stale-while-revalidate: return stale cache if available
            if let stale = await loadCached(id: cacheKey) {
                return stale
            }
            // No cache, no network: graceful nil (AC-W10-3)
            return nil
        }
    }

    // MARK: - Pure Computation

    /// Computes the count-weighted average rating from a distribution of
    /// per-storefront ratings.
    ///
    /// Formula: sum(averageRating_i * count_i) / sum(count_i)
    ///
    /// This is the same algorithm used by the iOS `RatingsReviewsViewModel`
    /// to aggregate across storefronts.
    ///
    /// - Parameter storefronts: Per-storefront rating data.
    /// - Returns: The weighted average, or `nil` if total count is zero.
    public static func computeWeightedAverage(
        from storefronts: [StorefrontRating]
    ) -> Double? {
        let totalCount = storefronts.reduce(0) { $0 + $1.ratingCount }
        guard totalCount > 0 else { return nil }

        let weightedSum = storefronts.reduce(0.0) { acc, info in
            acc + info.averageRating * Double(info.ratingCount)
        }
        return weightedSum / Double(totalCount)
    }

    /// Computes the weighted average from a star-rating distribution
    /// (counts per star 1..5).
    ///
    /// Formula: (5*c5 + 4*c4 + 3*c3 + 2*c2 + 1*c1) / (c5+c4+c3+c2+c1)
    ///
    /// This is the key unit-testable piece (TC-079).
    ///
    /// - Parameter distribution: A dictionary mapping star values (1...5)
    ///   to their counts. Keys outside 1...5 are ignored.
    /// - Returns: The weighted average, or `nil` if total count is zero.
    public static func computeWeightedAverage(
        from distribution: [Int: Int]
    ) -> Double? {
        var totalCount = 0
        var weightedSum = 0

        for star in 1...5 {
            let count = distribution[star] ?? 0
            totalCount += count
            weightedSum += star * count
        }

        guard totalCount > 0 else { return nil }
        return Double(weightedSum) / Double(totalCount)
    }

    // MARK: - Concurrent Multi-Storefront Lookup

    /// Outcome of a single-storefront lookup, distinguishing network errors
    /// from legitimate "app not found" responses.
    private enum StorefrontOutcome: Sendable {
        /// The storefront returned valid rating data.
        case found(StorefrontRating)
        /// The storefront responded successfully but the app has no ratings
        /// or is not available there.
        case notFound
        /// The request failed (network error, timeout, etc.).
        case failed
    }

    /// Queries every App Store storefront concurrently and returns the
    /// aggregated result.
    ///
    /// Mirrors the iOS `iTunesLookupAvailableStorefronts` implementation:
    /// - Launches one child task per storefront via `TaskGroup`
    /// - Each child decodes the JSON, extracts `averageUserRating` and
    ///   `userRatingCount`
    /// - Individual failures are swallowed (the storefront is skipped)
    /// - Results are sorted by country code for deterministic output
    /// - The aggregate weighted average is computed from the per-storefront
    ///   results
    ///
    /// If every single storefront request failed (total network failure),
    /// throws `ITunesLookupError.allStorefrontsFailed` so the caller can
    /// fall back to stale cache or return nil.
    ///
    /// - Parameter bundleId: The app's bundle identifier.
    /// - Returns: The `AggregateRating`.
    /// - Throws: `ITunesLookupError.allStorefrontsFailed` on total network failure.
    private func lookupAllStorefronts(bundleId: String) async throws -> AggregateRating {
        let outcomes: (storefronts: [StorefrontRating], successCount: Int) = await withTaskGroup(
            of: StorefrontOutcome.self,
            returning: (storefronts: [StorefrontRating], successCount: Int).self
        ) { group in
            for country in Self.appStoreStorefronts {
                group.addTask { [networking] in
                    await Self.lookupSingleStorefront(
                        bundleId: bundleId,
                        country: country,
                        networking: networking
                    )
                }
            }

            var results: [StorefrontRating] = []
            var successCount = 0
            for await outcome in group {
                switch outcome {
                case .found(let rating):
                    successCount += 1
                    results.append(rating)
                case .notFound:
                    successCount += 1
                case .failed:
                    break
                }
            }

            let filtered = results
                .filter { $0.averageRating > 0 }
                .sorted { $0.country < $1.country }

            return (storefronts: filtered, successCount: successCount)
        }

        // If no storefront responded successfully at all, treat it as a
        // total network failure (AC-W10-3).
        guard outcomes.successCount > 0 else {
            throw ITunesLookupError.allStorefrontsFailed
        }

        let storefronts = outcomes.storefronts
        let totalCount = storefronts.reduce(0) { $0 + $1.ratingCount }

        guard let weightedAverage = Self.computeWeightedAverage(from: storefronts) else {
            #if canImport(os)
            Logger(subsystem: "com.stackconnect.windows", category: "ITunesLookup")
                .info("[ITunesLookup] No ratings found for \(bundleId, privacy: .public) across \(Self.appStoreStorefronts.count) storefronts")
            #endif
            // Return a zero-rating aggregate rather than throwing, matching
            // iOS behavior where absent ratings are shown as 0/nil.
            return AggregateRating(
                averageRating: 0,
                totalCount: 0,
                storefrontCount: 0,
                storefronts: [],
                fetchedAt: dateProvider()
            )
        }

        #if canImport(os)
        Logger(subsystem: "com.stackconnect.windows", category: "ITunesLookup")
            .info("[ITunesLookup] Aggregated \(storefronts.count) storefronts for \(bundleId, privacy: .public): avg \(weightedAverage), count \(totalCount)")
        #endif

        return AggregateRating(
            averageRating: weightedAverage,
            totalCount: totalCount,
            storefrontCount: storefronts.count,
            storefronts: storefronts,
            fetchedAt: dateProvider()
        )
    }

    /// Fetches the iTunes Lookup result for a single storefront.
    ///
    /// Returns `.found` with rating data, `.notFound` when the API responded
    /// but the app has no data in that storefront, or `.failed` when the
    /// network request itself errored.
    private static func lookupSingleStorefront(
        bundleId: String,
        country: String,
        networking: ITunesLookupNetworking
    ) async -> StorefrontOutcome {
        let encodedBundleId = bundleId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? bundleId
        let urlString = "https://itunes.apple.com/lookup?bundleId=\(encodedBundleId)&country=\(country)"
        guard let url = URL(string: urlString) else { return .failed }

        do {
            let data = try await networking.fetchData(from: url)
            let response = try JSONDecoder().decode(LookupResponse.self, from: data)
            guard let app = response.results?.first,
                  let averageRating = app.averageUserRating,
                  let ratingCount = app.userRatingCount,
                  ratingCount > 0
            else {
                // API responded successfully but no rating data for this storefront.
                return .notFound
            }
            return .found(StorefrontRating(
                country: country,
                averageRating: averageRating,
                ratingCount: ratingCount
            ))
        } catch {
            // Network/decode failure for this storefront.
            return .failed
        }
    }

    // MARK: - Cache

    /// Storage key prefix for aggregate rating cache entries.
    private func cacheId(for bundleId: String) -> String {
        "itunes-rating.\(bundleId)"
    }

    /// Loads a cached `AggregateRating` from storage.
    private func loadCached(id: String) async -> AggregateRating? {
        do {
            return try await storage.fetch(AggregateRating.self, id: id)
        } catch {
            return nil
        }
    }

    /// Persists an `AggregateRating` to storage.
    private func saveToCache(_ rating: AggregateRating, id: String) async {
        do {
            try await storage.save(rating, id: id)
        } catch {
            #if canImport(os)
            Logger(subsystem: "com.stackconnect.windows", category: "ITunesLookup")
                .warning("[ITunesLookup] Failed to cache rating for \(id, privacy: .public): \(error.localizedDescription, privacy: .public)")
            #endif
        }
    }

    // MARK: - iTunes Lookup Response Models

    /// JSON response from the iTunes Lookup API.
    private struct LookupResponse: Decodable {
        let resultCount: Int?
        let results: [LookupApp]?
    }

    /// Single app entry within the lookup response.
    private struct LookupApp: Decodable {
        let averageUserRating: Double?
        let userRatingCount: Int?
    }

    // MARK: - Storefronts

    /// All App Store storefront codes (ISO 3166-1 alpha-2, lowercase).
    /// Source: https://en.wikipedia.org/wiki/App_Store_(Apple)#Distribution
    /// Matches the iOS `RatingsReviewsViewModel.appStoreStorefronts` list.
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
}
