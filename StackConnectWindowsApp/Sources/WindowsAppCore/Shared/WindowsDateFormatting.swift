import Foundation

// T-W04 — Pure-logic date formatting helpers for the Windows port.
//
// Provides two formatters consumed by review rows, app detail, and any other
// screen that needs human-readable dates:
//
//   1. `relativeDate(_:relativeTo:)` — time-ago string ("just now", "2h ago",
//      "3d ago", etc.). The `relativeTo` parameter defaults to `Date()` but
//      can be injected in tests for deterministic results.
//
//   2. `absoluteDate(_:)` — "d MMM yyyy" format (e.g. "21 May 2026").
//
// Both are Foundation-pure (no SwiftCrossUI, no UIKit) so they live in
// `WindowsAppCore` and are fully unit-testable on the macOS host.
//
// Note: `RelativeDateTimeFormatter` is Darwin-only; the non-Darwin path uses
// a simple manual calculation so there is no Apple-framework dependency leak
// into swift-corelibs-foundation.

/// Caseless namespace for date formatting utilities.
public enum WindowsDateFormatting {

    // MARK: - Relative date (time-ago)

    /// Returns a short relative date string (e.g. "just now", "5m ago",
    /// "2h ago", "3d ago", "1w ago").
    ///
    /// - Parameters:
    ///   - date: The date to format.
    ///   - now: The reference "current" date. Defaults to `Date()`. Pass a
    ///     fixed date in tests for deterministic output.
    /// - Returns: A human-readable relative time string.
    public static func relativeDate(_ date: Date, relativeTo now: Date = Date()) -> String {
        let seconds = Int(now.timeIntervalSince(date))

        // Future dates (or same instant) → "just now".
        guard seconds > 0 else { return "just now" }

        switch seconds {
        case ..<60:       return "just now"
        case ..<3_600:    return "\(seconds / 60)m ago"
        case ..<86_400:   return "\(seconds / 3_600)h ago"
        case ..<604_800:  return "\(seconds / 86_400)d ago"
        default:          return "\(seconds / 604_800)w ago"
        }
    }

    // MARK: - Absolute date ("d MMM yyyy")

    /// Cached formatter for `absoluteDate(_:timeZone:)`. Configured once with
    /// `en_US_POSIX` locale and `"d MMM yyyy"` format; `timeZone` is set per-call
    /// (safe for a single-threaded renderer). Mirrors the `private static let`
    /// caching pattern used by `AggregateRatingFormatter` (T-W17) to avoid
    /// allocating a new `DateFormatter` per row in the reviews list (T-W18
    /// Should-fix 1).
    private static let absoluteDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "d MMM yyyy"
        return f
    }()

    /// Formats a date as "d MMM yyyy" (e.g. "21 May 2026").
    ///
    /// The formatter uses the `en_US_POSIX` locale to guarantee a stable,
    /// deterministic output regardless of the user's system locale. This
    /// matches the design spec's "21 May 2026" example.
    ///
    /// - Parameters:
    ///   - date: The date to format.
    ///   - timeZone: The time zone for formatting. Defaults to `.current`.
    ///     Pass `TimeZone(identifier: "UTC")!` in tests for deterministic
    ///     output when the input dates are expressed in UTC.
    /// - Returns: A string in "d MMM yyyy" format.
    public static func absoluteDate(_ date: Date, timeZone: TimeZone = .current) -> String {
        absoluteDateFormatter.timeZone = timeZone
        return absoluteDateFormatter.string(from: date)
    }
}
