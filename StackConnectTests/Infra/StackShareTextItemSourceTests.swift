import LinkPresentation
import UIKit
import XCTest
@testable import StackConnect

@MainActor
final class StackShareTextItemSourceTests: XCTestCase {

    private func makeController(for source: StackShareTextItemSource) -> UIActivityViewController {
        UIActivityViewController(activityItems: [source], applicationActivities: nil)
    }

    func testSharesTheTextForEveryActivity() {
        let source = StackShareTextItemSource(text: "Hello")
        let controller = makeController(for: source)

        XCTAssertEqual(source.activityViewControllerPlaceholderItem(controller) as? String, "Hello")
        XCTAssertEqual(source.activityViewController(controller, itemForActivityType: .mail) as? String, "Hello")
        XCTAssertEqual(source.activityViewController(controller, itemForActivityType: nil) as? String, "Hello")
    }

    func testSubjectIsReturnedForMail() {
        let source = StackShareTextItemSource(text: "Hello", subject: "Action needed")

        XCTAssertEqual(source.activityViewController(makeController(for: source), subjectForActivityType: .mail), "Action needed")
    }

    func testMissingSubjectIsEmpty() {
        let source = StackShareTextItemSource(text: "Hello")

        XCTAssertEqual(source.activityViewController(makeController(for: source), subjectForActivityType: .mail), "")
    }

    func testLinkMetadataCarriesTitleAndURL() throws {
        let url = try XCTUnwrap(URL(string: "https://appstoreconnect.apple.com/agreements/"))
        let source = StackShareTextItemSource(
            text: "Hello",
            previewTitle: "Jane Appleseed <jane@example.com>",
            previewURL: url,
            previewIcon: UIImage(systemName: "person")
        )

        let metadata = try XCTUnwrap(source.activityViewControllerLinkMetadata(makeController(for: source)))

        XCTAssertEqual(metadata.title, "Jane Appleseed <jane@example.com>")
        XCTAssertEqual(metadata.originalURL, url)
        XCTAssertEqual(metadata.url, url)
        XCTAssertNotNil(metadata.iconProvider)
    }

    func testNoLinkMetadataWithoutTitle() {
        let source = StackShareTextItemSource(text: "Hello", previewURL: URL(string: "https://example.com"))

        XCTAssertNil(source.activityViewControllerLinkMetadata(makeController(for: source)))
    }
}
