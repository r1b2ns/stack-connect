import XCTest
@testable import StackConnect

final class DeepLinkTests: XCTestCase {

    func testRoundTripsAllCases() {
        let cases: [DeepLink] = [
            .home,
            .reviews,
            .app(accountId: "acc-1", appId: "123456"),
            .review(accountId: "acc-1", appId: "123456", reviewId: "rev-789")
        ]
        for link in cases {
            let parsed = DeepLink(url: link.url)
            XCTAssertEqual(parsed, link, "Round-trip failed for \(link)")
        }
    }

    func testParsesKnownURLs() {
        XCTAssertEqual(DeepLink(url: URL(string: "stackconnect://home")!), .home)
        XCTAssertEqual(DeepLink(url: URL(string: "stackconnect://reviews")!), .reviews)
        XCTAssertEqual(
            DeepLink(url: URL(string: "stackconnect://app/acc-1/123456")!),
            .app(accountId: "acc-1", appId: "123456")
        )
        XCTAssertEqual(
            DeepLink(url: URL(string: "stackconnect://review/acc-1/123456/rev-789")!),
            .review(accountId: "acc-1", appId: "123456", reviewId: "rev-789")
        )
    }

    func testRejectsForeignSchemeAndIncompletePaths() {
        XCTAssertNil(DeepLink(url: URL(string: "https://home")!))
        XCTAssertNil(DeepLink(url: URL(string: "stackconnect://app/only-account")!))
        XCTAssertNil(DeepLink(url: URL(string: "stackconnect://review/acc/app")!))
        XCTAssertNil(DeepLink(url: URL(string: "stackconnect://unknown")!))
    }
}
