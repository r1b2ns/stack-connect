import XCTest
@testable import StackConnect

/// Links built from store data only open the scheme they're meant to.
final class ExternalLinkURLTests: XCTestCase {

    // MARK: - Web

    func testWebKeepsHttpAndHttpsLinks() {
        XCTAssertEqual(ExternalLinkURL.web("https://example.com/support")?.absoluteString, "https://example.com/support")
        XCTAssertNotNil(ExternalLinkURL.web("HTTP://example.com"), "The scheme check ignores case")
        XCTAssertEqual(ExternalLinkURL.web("  https://youtu.be/abc \n")?.absoluteString, "https://youtu.be/abc")
    }

    func testWebOpensABareHostOverHttps() {
        XCTAssertEqual(ExternalLinkURL.web("example.com")?.absoluteString, "https://example.com")
        XCTAssertEqual(ExternalLinkURL.web("www.example.com/help")?.absoluteString, "https://www.example.com/help")
    }

    func testWebRefusesEveryOtherScheme() {
        let unsafe = [
            "javascript:alert(1)",
            "file:///etc/passwd",
            "itms-services://?action=download-manifest&url=https://evil.example/app.plist",
            "tel:+15550100",
            "mailto:dev@example.com",
            "sms:+15550100",
            "myapp://open",
            "data:text/html,<script>alert(1)</script>"
        ]
        for value in unsafe {
            XCTAssertNil(ExternalLinkURL.web(value), value)
        }
    }

    func testWebRefusesEmptyAndHostlessValues() {
        XCTAssertNil(ExternalLinkURL.web(""))
        XCTAssertNil(ExternalLinkURL.web("   "))
        XCTAssertNil(ExternalLinkURL.web("https://"))
    }

    // MARK: - Email

    func testEmailBuildsAMailtoLink() {
        XCTAssertEqual(ExternalLinkURL.email("dev@example.com")?.absoluteString, "mailto:dev@example.com")
        XCTAssertEqual(ExternalLinkURL.email(" dev@example.com ")?.absoluteString, "mailto:dev@example.com")
    }

    func testEmailRefusesAnythingButAPlainAddress() {
        let invalid = ["", "dev", "@example.com", "dev@", "a@b@c", "dev @example.com", "dev@example.com?subject=x", "javascript:x@y"]
        for value in invalid {
            XCTAssertNil(ExternalLinkURL.email(value), value)
        }
    }

    // MARK: - Phone

    func testPhoneKeepsOnlyDialableCharacters() {
        XCTAssertEqual(ExternalLinkURL.phone("+1 (555) 010-0100")?.absoluteString, "tel:+15550100100")
        XCTAssertNil(ExternalLinkURL.phone("call us"))
        XCTAssertNil(ExternalLinkURL.phone(""))
    }
}
