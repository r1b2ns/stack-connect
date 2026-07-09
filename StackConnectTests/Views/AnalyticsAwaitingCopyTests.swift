import XCTest
@testable import StackConnect

final class AnalyticsAwaitingCopyTests: XCTestCase {

    /// A fixed reference "now" so relative/expected-by phrasing is deterministic.
    /// (RelativeDateTimeFormatter / DateFormatter output is locale-dependent, so
    /// the assertions below only check stable, English substrings — never the
    /// exact relative phrase.)
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private var sixHours: TimeInterval { 6 * 60 * 60 }
    private var seventyTwoHours: TimeInterval { 72 * 60 * 60 }

    // MARK: - window

    func testWindowIs48Hours() {
        XCTAssertEqual(AnalyticsAwaitingCopy.window, 48 * 60 * 60)
    }

    // MARK: - isOverdue

    func testIsOverdueFalseBeforeWindow() {
        let requestedAt = now.addingTimeInterval(-sixHours)

        XCTAssertFalse(AnalyticsAwaitingCopy.isOverdue(requestedAt: requestedAt, now: now))
    }

    func testIsOverdueTrueAfterWindow() {
        let requestedAt = now.addingTimeInterval(-seventyTwoHours)

        XCTAssertTrue(AnalyticsAwaitingCopy.isOverdue(requestedAt: requestedAt, now: now))
    }

    func testIsOverdueTrueExactlyAtBoundary() {
        let requestedAt = now.addingTimeInterval(-AnalyticsAwaitingCopy.window)

        XCTAssertTrue(
            AnalyticsAwaitingCopy.isOverdue(requestedAt: requestedAt, now: now),
            "The boundary is inclusive (>=)."
        )
    }

    // MARK: - detail

    func testDetailWithoutRequestedAtIsTheGenericString() {
        let text = AnalyticsAwaitingCopy.detail(requestedAt: nil, isOverdue: false, now: now)

        XCTAssertTrue(text.contains("This report has been requested"))
    }

    func testDetailBeforeWindowMentionsWindowAndIsNotOverdue() {
        let requestedAt = now.addingTimeInterval(-sixHours)

        let text = AnalyticsAwaitingCopy.detail(requestedAt: requestedAt, isOverdue: false, now: now)

        XCTAssertFalse(AnalyticsAwaitingCopy.isOverdue(requestedAt: requestedAt, now: now))
        XCTAssertTrue(text.contains("24–48 hours"))
        XCTAssertFalse(text.contains("taking longer"))
    }

    func testDetailAfterWindowMentionsTakingLonger() {
        let requestedAt = now.addingTimeInterval(-seventyTwoHours)

        let text = AnalyticsAwaitingCopy.detail(requestedAt: requestedAt, isOverdue: true, now: now)

        XCTAssertTrue(AnalyticsAwaitingCopy.isOverdue(requestedAt: requestedAt, now: now))
        XCTAssertTrue(text.contains("taking longer"))
    }
}
