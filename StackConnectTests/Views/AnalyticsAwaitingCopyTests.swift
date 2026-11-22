import XCTest
@testable import StackConnect

final class AnalyticsAwaitingCopyTests: XCTestCase {

    /// A fixed reference "now" so relative/expected-by phrasing is deterministic.
    /// Expected copy is built the way production builds it (same localized key,
    /// same `RelativeDateTimeFormatter` / `DateFormatter` setup), so the
    /// assertions hold in any simulator language.
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    /// The relative phrase production interpolates, e.g. "6 hours ago".
    private func relativePhrase(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: now)
    }

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

        XCTAssertEqual(text, String(localized: "This report has been requested. Apple usually publishes the data within 24–48 hours."))
    }

    func testDetailBeforeWindowMentionsWindowAndIsNotOverdue() {
        let requestedAt = now.addingTimeInterval(-sixHours)

        let text = AnalyticsAwaitingCopy.detail(requestedAt: requestedAt, isOverdue: false, now: now)

        XCTAssertFalse(AnalyticsAwaitingCopy.isOverdue(requestedAt: requestedAt, now: now))
        let phrase = relativePhrase(requestedAt)
        XCTAssertEqual(text, String(localized: "Requested \(phrase). Apple usually publishes analytics data within 24–48 hours of the request."))
        XCTAssertNotEqual(text, String(localized: "Requested \(phrase). This is taking longer than the usual 24–48 hours — some report types aren't produced for every app."))
    }

    func testDetailAfterWindowMentionsTakingLonger() {
        let requestedAt = now.addingTimeInterval(-seventyTwoHours)

        let text = AnalyticsAwaitingCopy.detail(requestedAt: requestedAt, isOverdue: true, now: now)

        XCTAssertTrue(AnalyticsAwaitingCopy.isOverdue(requestedAt: requestedAt, now: now))
        let phrase = relativePhrase(requestedAt)
        XCTAssertEqual(text, String(localized: "Requested \(phrase). This is taking longer than the usual 24–48 hours — some report types aren't produced for every app."))
    }
}
