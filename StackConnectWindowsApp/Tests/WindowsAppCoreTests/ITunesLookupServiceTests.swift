import XCTest
import StackProtocols
@testable import WindowsAppCore

// MARK: - Mock Networking

/// In-memory mock for `ITunesLookupNetworking` that returns canned responses
/// per URL and tracks call counts. Thread-safe: mutable counters are
/// protected by `NSLock` since `fetchData` is called from 175 concurrent
/// TaskGroup children. `responses` and `shouldThrowAll` are set BEFORE any
/// concurrent access begins (during test setup), so they are safe.
final class MockLookupNetworking: ITunesLookupNetworking, @unchecked Sendable {

    /// Canned responses keyed by URL string. If a URL is not in this map,
    /// the mock throws `URLError(.badServerResponse)`.
    /// Set during test setup ONLY (before any concurrent access).
    var responses: [String: Result<Data, Error>] = [:]

    /// When true, ALL requests throw (simulates total network failure).
    /// Set during test setup ONLY (before any concurrent access).
    var shouldThrowAll = false

    /// Lock protecting mutable counters accessed from concurrent tasks.
    private let lock = NSLock()
    private var _fetchCallCount = 0
    private var _fetchedURLs: [URL] = []

    /// Number of `fetchData` calls made.
    var fetchCallCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _fetchCallCount
    }

    /// All URLs that were fetched.
    var fetchedURLs: [URL] {
        lock.lock()
        defer { lock.unlock() }
        return _fetchedURLs
    }

    func fetchData(from url: URL) async throws -> Data {
        lock.lock()
        _fetchCallCount += 1
        _fetchedURLs.append(url)
        lock.unlock()

        if shouldThrowAll {
            throw URLError(.notConnectedToInternet)
        }

        if let result = responses[url.absoluteString] {
            return try result.get()
        }

        throw URLError(.badServerResponse)
    }
}

// MARK: - Test Helpers

/// Builds a valid iTunes Lookup JSON response for a single app.
private func makeLookupJSON(averageRating: Double?, ratingCount: Int?) -> Data {
    var fields: [String] = []
    if let avg = averageRating {
        fields.append("\"averageUserRating\": \(avg)")
    }
    if let count = ratingCount {
        fields.append("\"userRatingCount\": \(count)")
    }
    let appJSON = "{\(fields.joined(separator: ", "))}"
    let json = """
    {"resultCount": 1, "results": [\(appJSON)]}
    """
    return Data(json.utf8)
}

/// Builds an empty iTunes Lookup JSON response (app not available in that storefront).
private func makeEmptyLookupJSON() -> Data {
    Data("""
    {"resultCount": 0, "results": []}
    """.utf8)
}

// MARK: - Tests

/// Unit tests for `ITunesLookupService` (T-W15).
///
/// Covers:
/// - TC-079: `computeWeightedAverage` with the spec distribution and edge cases
/// - Cache behavior: hit within TTL, stale triggers refresh, failure graceful nil
/// - Concurrent multi-storefront lookup with mocked networking
/// - Graceful failure (AC-W10-3)
@MainActor
final class ITunesLookupServiceTests: XCTestCase {

    private var storage: MockStorage!
    private var networking: MockLookupNetworking!

    /// Thread-safe mutable date for deterministic TTL testing.
    /// Wrapped in a class so the `@Sendable` closure can capture it
    /// without violating `@MainActor` isolation.
    private final class DateBox: @unchecked Sendable {
        var value: Date
        init(_ value: Date) { self.value = value }
    }

    private var dateBox: DateBox!

    /// Convenience accessor for the current test date.
    private var currentDate: Date {
        get { dateBox.value }
        set { dateBox.value = newValue }
    }

    override func setUp() async throws {
        try await super.setUp()
        storage = MockStorage()
        networking = MockLookupNetworking()
        dateBox = DateBox(Date(timeIntervalSince1970: 1_700_000_000)) // 2023-11-14
    }

    override func tearDown() async throws {
        storage = nil
        networking = nil
        dateBox = nil
        try await super.tearDown()
    }

    /// Helper: creates a SUT with the shared test dependencies.
    private func makeSUT(cacheTTL: TimeInterval = 3600) -> ITunesLookupService {
        let box = dateBox!
        return ITunesLookupService(
            networking: networking,
            storage: storage,
            cacheTTL: cacheTTL,
            dateProvider: { box.value }
        )
    }

    /// Seeds a canned response for a specific country's lookup URL.
    private func seedResponse(
        bundleId: String,
        country: String,
        averageRating: Double,
        ratingCount: Int
    ) {
        let url = "https://itunes.apple.com/lookup?bundleId=\(bundleId)&country=\(country)"
        networking.responses[url] = .success(
            makeLookupJSON(averageRating: averageRating, ratingCount: ratingCount)
        )
    }

    /// Seeds empty responses (app not found) for a specific country.
    private func seedEmptyResponse(bundleId: String, country: String) {
        let url = "https://itunes.apple.com/lookup?bundleId=\(bundleId)&country=\(country)"
        networking.responses[url] = .success(makeEmptyLookupJSON())
    }

    // MARK: - TC-079: computeWeightedAverage (star distribution)

    /// TC-079 primary assertion:
    /// [5:30000, 4:8000, 3:2000, 2:1000, 1:1300]
    ///
    /// The spec formula: (5*30000 + 4*8000 + 3*2000 + 2*1000 + 1*1300)
    ///                    / (30000 + 8000 + 2000 + 1000 + 1300)
    ///                  = 191300 / 42300 ≈ 4.5248
    ///
    /// The spec text says "approximately 4.8" but the formula itself yields
    /// ~4.525. We assert against the formula result (the ground truth) with
    /// +/-0.01 tolerance as the spec requires.
    func testComputeWeightedAverageSpecDistribution() {
        let distribution: [Int: Int] = [5: 30000, 4: 8000, 3: 2000, 2: 1000, 1: 1300]
        let result = ITunesLookupService.computeWeightedAverage(from: distribution)

        XCTAssertNotNil(result)
        let expected = 191300.0 / 42300.0 // ≈ 4.5248
        XCTAssertEqual(result!, expected, accuracy: 0.01)
        XCTAssertGreaterThan(result!, 4.0)
        XCTAssertLessThanOrEqual(result!, 5.0)
    }

    /// Edge case: empty distribution (zero total) returns nil.
    func testComputeWeightedAverageEmptyDistribution() {
        let result = ITunesLookupService.computeWeightedAverage(from: [:] as [Int: Int])
        XCTAssertNil(result)
    }

    /// Edge case: all-zero distribution returns nil.
    func testComputeWeightedAverageAllZeroDistribution() {
        let distribution: [Int: Int] = [5: 0, 4: 0, 3: 0, 2: 0, 1: 0]
        let result = ITunesLookupService.computeWeightedAverage(from: distribution)
        XCTAssertNil(result)
    }

    /// Edge case: single bucket (all 5-star) returns 5.0.
    func testComputeWeightedAverageSingleBucket() {
        let distribution: [Int: Int] = [5: 100]
        let result = ITunesLookupService.computeWeightedAverage(from: distribution)

        XCTAssertNotNil(result)
        XCTAssertEqual(result!, 5.0, accuracy: 0.001)
    }

    /// Edge case: single bucket (all 1-star) returns 1.0.
    func testComputeWeightedAverageAllOneStar() {
        let distribution: [Int: Int] = [1: 500]
        let result = ITunesLookupService.computeWeightedAverage(from: distribution)

        XCTAssertNotNil(result)
        XCTAssertEqual(result!, 1.0, accuracy: 0.001)
    }

    /// Edge case: equal counts across all stars returns 3.0.
    func testComputeWeightedAverageAllEqual() {
        let distribution: [Int: Int] = [5: 100, 4: 100, 3: 100, 2: 100, 1: 100]
        let result = ITunesLookupService.computeWeightedAverage(from: distribution)

        XCTAssertNotNil(result)
        // (5*100 + 4*100 + 3*100 + 2*100 + 1*100) / 500 = 1500/500 = 3.0
        XCTAssertEqual(result!, 3.0, accuracy: 0.001)
    }

    /// Edge case: large counts do not overflow (Int is 64-bit on all platforms).
    func testComputeWeightedAverageLargeCounts() {
        let distribution: [Int: Int] = [
            5: 1_000_000_000,
            4: 500_000_000,
            3: 200_000_000,
            2: 100_000_000,
            1: 50_000_000
        ]
        let result = ITunesLookupService.computeWeightedAverage(from: distribution)

        XCTAssertNotNil(result)
        // Should be a value close to 4.24 (heavily weighted toward 5 stars)
        XCTAssertGreaterThan(result!, 4.0)
        XCTAssertLessThanOrEqual(result!, 5.0)
    }

    /// Keys outside 1...5 are ignored.
    func testComputeWeightedAverageIgnoresOutOfRangeKeys() {
        let distribution: [Int: Int] = [0: 999, 5: 10, 6: 999, 10: 999]
        let result = ITunesLookupService.computeWeightedAverage(from: distribution)

        XCTAssertNotNil(result)
        XCTAssertEqual(result!, 5.0, accuracy: 0.001)
    }

    // MARK: - computeWeightedAverage (storefront variant)

    /// Storefront-weighted average matches the iOS formula.
    func testComputeWeightedAverageFromStorefronts() {
        let storefronts = [
            StorefrontRating(country: "us", averageRating: 4.5, ratingCount: 10000),
            StorefrontRating(country: "gb", averageRating: 4.0, ratingCount: 5000),
            StorefrontRating(country: "de", averageRating: 3.5, ratingCount: 3000),
        ]

        let result = ITunesLookupService.computeWeightedAverage(from: storefronts)

        XCTAssertNotNil(result)
        // (4.5*10000 + 4.0*5000 + 3.5*3000) / (10000+5000+3000)
        // = (45000 + 20000 + 10500) / 18000
        // = 75500 / 18000
        // ≈ 4.194
        XCTAssertEqual(result!, 75500.0 / 18000.0, accuracy: 0.001)
    }

    /// Empty storefronts returns nil.
    func testComputeWeightedAverageFromStorefrontsEmpty() {
        let result = ITunesLookupService.computeWeightedAverage(from: [] as [StorefrontRating])
        XCTAssertNil(result)
    }

    // MARK: - Cache Hit Within TTL

    /// When a fresh cache entry exists, `fetchAggregateRating` returns it
    /// without making any network calls.
    func testCacheHitWithinTTLServesWithoutNetwork() async {
        let sut = makeSUT(cacheTTL: 3600)

        // Pre-seed cache with a fresh entry
        let cached = AggregateRating(
            averageRating: 4.5,
            totalCount: 10000,
            storefrontCount: 5,
            storefronts: [
                StorefrontRating(country: "us", averageRating: 4.5, ratingCount: 10000)
            ],
            fetchedAt: currentDate // Fetched "now" (age = 0)
        )
        try! await storage.save(cached, id: "itunes-rating.com.example.app")

        let result = await sut.fetchAggregateRating(bundleId: "com.example.app")

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.averageRating, 4.5)
        XCTAssertEqual(result?.totalCount, 10000)
        // No network calls should have been made
        XCTAssertEqual(networking.fetchCallCount, 0)
    }

    // MARK: - Stale Cache Triggers Refresh

    /// When the cache is stale (age > TTL), the service refreshes from the
    /// network and updates the cache.
    func testStaleCacheTriggersRefresh() async {
        let sut = makeSUT(cacheTTL: 3600)

        // Pre-seed cache with a stale entry (fetchedAt 2 hours ago)
        let staleDate = currentDate.addingTimeInterval(-7200) // 2 hours ago
        let stale = AggregateRating(
            averageRating: 4.0,
            totalCount: 5000,
            storefrontCount: 3,
            storefronts: [],
            fetchedAt: staleDate
        )
        try! await storage.save(stale, id: "itunes-rating.com.example.app")

        // Seed network responses for only 2 storefronts (the rest will 404/error)
        seedResponse(bundleId: "com.example.app", country: "us", averageRating: 4.8, ratingCount: 20000)
        seedResponse(bundleId: "com.example.app", country: "gb", averageRating: 4.2, ratingCount: 5000)

        let result = await sut.fetchAggregateRating(bundleId: "com.example.app")

        XCTAssertNotNil(result)
        // Network was called (at least for the storefronts)
        XCTAssertGreaterThan(networking.fetchCallCount, 0)
        // The result should reflect the new data (us + gb)
        XCTAssertEqual(result?.storefrontCount, 2)
        // Cache should be updated (fetchedAt should be "now")
        XCTAssertEqual(result?.fetchedAt, currentDate)
    }

    // MARK: - Stale-While-Revalidate on Network Failure

    /// When the cache is stale and the network fails, the stale cache is
    /// returned (stale-while-revalidate).
    func testStaleWhileRevalidateOnNetworkFailure() async {
        let sut = makeSUT(cacheTTL: 3600)

        // Pre-seed cache with a stale entry
        let staleDate = currentDate.addingTimeInterval(-7200)
        let stale = AggregateRating(
            averageRating: 4.0,
            totalCount: 5000,
            storefrontCount: 3,
            storefronts: [],
            fetchedAt: staleDate
        )
        try! await storage.save(stale, id: "itunes-rating.com.example.app")

        // Network fails for all storefronts
        networking.shouldThrowAll = true

        let result = await sut.fetchAggregateRating(bundleId: "com.example.app")

        // Should return stale data
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.averageRating, 4.0)
        XCTAssertEqual(result?.totalCount, 5000)
        XCTAssertEqual(result?.fetchedAt, staleDate)
    }

    // MARK: - Graceful Failure (AC-W10-3)

    /// When there is no cache AND the network fails, the service returns nil
    /// (graceful failure, no crash).
    func testGracefulNilOnTotalFailure() async {
        let sut = makeSUT()

        // No cache, network fails
        networking.shouldThrowAll = true

        let result = await sut.fetchAggregateRating(bundleId: "com.nonexistent.app")

        XCTAssertNil(result, "Should return nil gracefully when no cache and network fails")
        // No crash — the test completing is the assertion.
    }

    // MARK: - Multi-Storefront Aggregation

    /// Verifies that the service aggregates across multiple storefronts
    /// correctly using count-weighted averaging.
    func testMultiStorefrontAggregation() async {
        let sut = makeSUT()

        // Seed responses for 3 storefronts
        seedResponse(bundleId: "com.test.app", country: "us", averageRating: 4.5, ratingCount: 10000)
        seedResponse(bundleId: "com.test.app", country: "gb", averageRating: 4.0, ratingCount: 5000)
        seedResponse(bundleId: "com.test.app", country: "jp", averageRating: 3.5, ratingCount: 3000)

        let result = await sut.fetchAggregateRating(bundleId: "com.test.app")

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.storefrontCount, 3)
        XCTAssertEqual(result?.totalCount, 18000)

        // Expected weighted average: (4.5*10000 + 4.0*5000 + 3.5*3000) / 18000
        let expectedAvg = 75500.0 / 18000.0
        XCTAssertEqual(result!.averageRating, expectedAvg, accuracy: 0.01)

        // Storefronts should be sorted by country code
        XCTAssertEqual(result?.storefronts[0].country, "gb")
        XCTAssertEqual(result?.storefronts[1].country, "jp")
        XCTAssertEqual(result?.storefronts[2].country, "us")
    }

    // MARK: - No Ratings Found

    /// When no storefront has any rating data, the service returns a
    /// zero-rating aggregate (not nil, matching iOS behavior).
    func testNoRatingsReturnsZeroAggregate() async {
        let sut = makeSUT()

        // All storefronts return empty lookup
        for country in ITunesLookupService.appStoreStorefronts {
            seedEmptyResponse(bundleId: "com.new.app", country: country)
        }

        let result = await sut.fetchAggregateRating(bundleId: "com.new.app")

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.averageRating, 0)
        XCTAssertEqual(result?.totalCount, 0)
        XCTAssertEqual(result?.storefrontCount, 0)
    }

    // MARK: - Cache Is Persisted After Lookup

    /// After a successful lookup, the result is persisted in storage so
    /// subsequent calls within TTL serve from cache.
    func testResultIsPersistedAfterLookup() async {
        let sut = makeSUT()

        seedResponse(bundleId: "com.cache.test", country: "us", averageRating: 4.9, ratingCount: 500)

        let result1 = await sut.fetchAggregateRating(bundleId: "com.cache.test")
        XCTAssertNotNil(result1)

        let callCountAfterFirst = networking.fetchCallCount

        // Second call should hit cache (no new network calls)
        let result2 = await sut.fetchAggregateRating(bundleId: "com.cache.test")
        XCTAssertNotNil(result2)
        XCTAssertEqual(result2?.averageRating, result1?.averageRating)
        XCTAssertEqual(networking.fetchCallCount, callCountAfterFirst,
                       "Second call within TTL should not trigger network calls")
    }

    // MARK: - Storefront Count Matches iOS List

    /// Verifies the storefront list contains 169 entries matching the iOS
    /// `RatingsReviewsViewModel.appStoreStorefronts` list.
    func testStorefrontCountMatchesiOS() {
        let count = ITunesLookupService.appStoreStorefronts.count
        XCTAssertEqual(count, 169)
    }

    // MARK: - Zero-RatingCount Storefronts Are Filtered

    /// Storefronts with ratingCount == 0 (or averageRating == 0) are excluded
    /// from the aggregate, matching iOS behavior.
    func testZeroRatingCountFilteredOut() async {
        let sut = makeSUT()

        seedResponse(bundleId: "com.filter.test", country: "us", averageRating: 4.5, ratingCount: 1000)
        // GB has rating but zero count — should be filtered
        let gbURL = "https://itunes.apple.com/lookup?bundleId=com.filter.test&country=gb"
        networking.responses[gbURL] = .success(makeLookupJSON(averageRating: 3.0, ratingCount: 0))

        let result = await sut.fetchAggregateRating(bundleId: "com.filter.test")

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.storefrontCount, 1)
        XCTAssertEqual(result?.storefronts.first?.country, "us")
    }
}
