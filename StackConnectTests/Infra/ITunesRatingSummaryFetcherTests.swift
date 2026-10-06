import XCTest
@testable import StackConnect

/// The App Store rating summary sweep, over a stubbed iTunes Lookup.
final class ITunesRatingSummaryFetcherTests: XCTestCase {

    /// iTunes Lookup body for one storefront; `nil` rating = app not listed there.
    private static func lookupJSON(average: Double?, count: Int?) -> Data {
        guard let average else {
            return Data(#"{"resultCount":0,"results":[]}"#.utf8)
        }
        let countField = count.map { ",\"userRatingCount\":\($0)" } ?? ""
        return Data(#"{"resultCount":1,"results":[{"averageUserRating":\#(average)\#(countField)}]}"#.utf8)
    }

    private static func country(of url: URL) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "country" }?.value
    }

    func testAggregatesACountWeightedAverageAcrossStorefronts() async throws {
        let fetcher = ITunesRatingSummaryFetcher(storefronts: ["us", "br", "de", "jp"]) { url in
            switch Self.country(of: url) {
            case "us": return Self.lookupJSON(average: 4.0, count: 300)
            case "br": return Self.lookupJSON(average: 5.0, count: 100)
            case "de": return Self.lookupJSON(average: nil, count: nil)   // not sold there
            default:   return Self.lookupJSON(average: 0, count: 0)      // listed, no ratings
            }
        }

        let result = await fetcher.fetchSummary(bundleId: "com.example.ios")
        let summary = try XCTUnwrap(result)

        XCTAssertTrue(summary.isComplete)
        XCTAssertEqual(summary.storefronts.map(\.country), ["br", "us"], "Rated storefronts only, by country")
        XCTAssertEqual(summary.ratingCount, 400)
        XCTAssertEqual(try XCTUnwrap(summary.averageRating), 4.25, accuracy: 0.0001)
    }

    func testAsksEveryStorefrontForTheBundleId() async {
        let urls = URLRecorder()
        let fetcher = ITunesRatingSummaryFetcher(storefronts: ["us", "gb"]) { url in
            urls.append(url)
            return Self.lookupJSON(average: nil, count: nil)
        }

        _ = await fetcher.fetchSummary(bundleId: "com.example.ios")

        let queries = urls.values.compactMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }
        XCTAssertEqual(Set(queries.compactMap { $0.queryItems?.first { $0.name == "country" }?.value }), ["us", "gb"])
        XCTAssertTrue(queries.allSatisfy { $0.host == "itunes.apple.com" && $0.path == "/lookup" })
        XCTAssertTrue(queries.allSatisfy { $0.queryItems?.contains(URLQueryItem(name: "bundleId", value: "com.example.ios")) == true })
    }

    func testNoRatingsYetHasNoAverage() async throws {
        let fetcher = ITunesRatingSummaryFetcher(storefronts: ["us"]) { _ in Self.lookupJSON(average: nil, count: nil) }

        let result = await fetcher.fetchSummary(bundleId: "com.example.ios")
        let summary = try XCTUnwrap(result)

        XCTAssertTrue(summary.isComplete)
        XCTAssertNil(summary.averageRating)
        XCTAssertEqual(summary.ratingCount, 0)
    }

    /// A storefront that couldn't be asked makes the numbers undercount.
    func testFailedStorefrontsMakeThePartialSummaryIncomplete() async throws {
        let fetcher = ITunesRatingSummaryFetcher(storefronts: ["us", "br", "jp"]) { url in
            switch Self.country(of: url) {
            case "us": return Self.lookupJSON(average: 4.0, count: 10)
            case "br": throw URLError(.timedOut)
            default:   return Data("not json".utf8)
            }
        }

        let result = await fetcher.fetchSummary(bundleId: "com.example.ios")
        let summary = try XCTUnwrap(result)

        XCTAssertFalse(summary.isComplete)
        XCTAssertEqual(summary.ratingCount, 10)
    }

    /// Cancelled half-way, the sweep reports nothing rather than a partial
    /// summary the screen would show as the real one.
    func testCancelledSweepReportsNothing() async {
        let fetcher = ITunesRatingSummaryFetcher(storefronts: ["us", "br"]) { _ in
            try await Task.sleep(nanoseconds: 5_000_000_000)
            return Self.lookupJSON(average: 4.0, count: 10)
        }

        let sweep = Task { await fetcher.fetchSummary(bundleId: "com.example.ios") }
        sweep.cancel()
        let summary = await sweep.value

        XCTAssertNil(summary)
    }
}

/// Thread-safe list of requested URLs for a `@Sendable` stub.
private final class URLRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var _values: [URL] = []

    var values: [URL] { lock.withLock { _values } }

    func append(_ url: URL) {
        lock.withLock { _values.append(url) }
    }
}
