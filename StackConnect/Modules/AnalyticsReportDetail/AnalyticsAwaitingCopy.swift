import Foundation

// MARK: - Awaiting-state copy

/// Non-generic, testable helper that produces the user-facing copy for the
/// "awaiting data" state of the analytics report detail screen.
///
/// It lives outside the generic `AnalyticsReportDetailView` (a generic type
/// can't hold static stored properties and its `private static` helpers aren't
/// reachable from tests) so the 48h threshold and the relative / expected-by
/// phrasing can be unit-tested deterministically. Every time-sensitive call
/// takes an explicit `now`, and the overdue threshold is defined in exactly one
/// place (`window`).
enum AnalyticsAwaitingCopy {

    /// The usual Apple analytics publication window (48 hours), in seconds.
    static let window: TimeInterval = 48 * 60 * 60

    /// Whether the publication window has already elapsed, relative to `now`
    /// (inclusive at the boundary).
    static func isOverdue(requestedAt: Date, now: Date) -> Bool {
        now.timeIntervalSince(requestedAt) >= window
    }

    /// Detail copy for the awaiting state, tuned to whether the POST time is
    /// known and whether the 24–48h window has already elapsed relative to
    /// `now`.
    static func detail(requestedAt: Date?, isOverdue: Bool, now: Date) -> String {
        guard let requestedAt else {
            return String(localized: "This report has been requested. Apple usually publishes the data within 24–48 hours.")
        }
        let relative = relativeString(for: requestedAt, now: now)
        if isOverdue {
            return String(localized: "Requested \(relative). This is taking longer than the usual 24–48 hours — some report types aren't produced for every app.")
        }
        return String(localized: "Requested \(relative). Apple usually publishes analytics data within 24–48 hours of the request.")
    }

    /// Secondary caption giving the medium-formatted date `window` after the
    /// request.
    static func expectedBy(requestedAt: Date) -> String {
        let expected = requestedAt.addingTimeInterval(window)
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return String(localized: "Expected by \(formatter.string(from: expected))")
    }

    /// Human-relative phrasing of a past date relative to `now`, e.g. "6 hours
    /// ago".
    private static func relativeString(for date: Date, now: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: now)
    }
}
