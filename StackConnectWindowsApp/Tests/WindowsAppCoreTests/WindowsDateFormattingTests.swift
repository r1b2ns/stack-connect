import XCTest
@testable import WindowsAppCore

/// Unit tests for `WindowsDateFormatting` (T-W04 AC-4).
///
/// All relative-date tests inject a fixed `now` so the output is
/// deterministic and independent of the wall clock.
final class WindowsDateFormattingTests: XCTestCase {

    // MARK: - Helpers

    /// A fixed reference date: 2026-05-21 12:00:00 UTC.
    private var referenceDate: Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 5
        components.day = 21
        components.hour = 12
        components.minute = 0
        components.second = 0
        components.timeZone = TimeZone(identifier: "UTC")
        return Calendar.current.date(from: components)!
    }

    /// Returns a date that is `seconds` before `referenceDate`.
    private func dateBefore(_ seconds: Int) -> Date {
        referenceDate.addingTimeInterval(-Double(seconds))
    }

    // MARK: - relativeDate tests

    func testJustNow_zeroSeconds() {
        let result = WindowsDateFormatting.relativeDate(referenceDate, relativeTo: referenceDate)
        XCTAssertEqual(result, "just now")
    }

    func testJustNow_fewSeconds() {
        let date = dateBefore(30)
        let result = WindowsDateFormatting.relativeDate(date, relativeTo: referenceDate)
        XCTAssertEqual(result, "just now")
    }

    func testJustNow_futureDate() {
        let futureDate = referenceDate.addingTimeInterval(60)
        let result = WindowsDateFormatting.relativeDate(futureDate, relativeTo: referenceDate)
        XCTAssertEqual(result, "just now", "Future dates should show 'just now'")
    }

    func testMinutesAgo() {
        let date = dateBefore(120) // 2 minutes
        let result = WindowsDateFormatting.relativeDate(date, relativeTo: referenceDate)
        XCTAssertEqual(result, "2m ago")
    }

    func testMinutesAgo_59Minutes() {
        let date = dateBefore(59 * 60) // 59 minutes
        let result = WindowsDateFormatting.relativeDate(date, relativeTo: referenceDate)
        XCTAssertEqual(result, "59m ago")
    }

    func testHoursAgo() {
        let date = dateBefore(2 * 3_600) // 2 hours
        let result = WindowsDateFormatting.relativeDate(date, relativeTo: referenceDate)
        XCTAssertEqual(result, "2h ago")
    }

    func testHoursAgo_23Hours() {
        let date = dateBefore(23 * 3_600) // 23 hours
        let result = WindowsDateFormatting.relativeDate(date, relativeTo: referenceDate)
        XCTAssertEqual(result, "23h ago")
    }

    func testDaysAgo() {
        let date = dateBefore(3 * 86_400) // 3 days
        let result = WindowsDateFormatting.relativeDate(date, relativeTo: referenceDate)
        XCTAssertEqual(result, "3d ago")
    }

    func testDaysAgo_6Days() {
        let date = dateBefore(6 * 86_400) // 6 days
        let result = WindowsDateFormatting.relativeDate(date, relativeTo: referenceDate)
        XCTAssertEqual(result, "6d ago")
    }

    func testWeeksAgo() {
        let date = dateBefore(2 * 604_800) // 2 weeks
        let result = WindowsDateFormatting.relativeDate(date, relativeTo: referenceDate)
        XCTAssertEqual(result, "2w ago")
    }

    func testWeeksAgo_manyWeeks() {
        let date = dateBefore(10 * 604_800) // 10 weeks
        let result = WindowsDateFormatting.relativeDate(date, relativeTo: referenceDate)
        XCTAssertEqual(result, "10w ago")
    }

    func testBoundary_exactly60Seconds() {
        let date = dateBefore(60) // exactly 1 minute
        let result = WindowsDateFormatting.relativeDate(date, relativeTo: referenceDate)
        XCTAssertEqual(result, "1m ago")
    }

    func testBoundary_exactly1Hour() {
        let date = dateBefore(3_600) // exactly 1 hour
        let result = WindowsDateFormatting.relativeDate(date, relativeTo: referenceDate)
        XCTAssertEqual(result, "1h ago")
    }

    func testBoundary_exactly1Day() {
        let date = dateBefore(86_400) // exactly 1 day
        let result = WindowsDateFormatting.relativeDate(date, relativeTo: referenceDate)
        XCTAssertEqual(result, "1d ago")
    }

    func testBoundary_exactly1Week() {
        let date = dateBefore(604_800) // exactly 1 week
        let result = WindowsDateFormatting.relativeDate(date, relativeTo: referenceDate)
        XCTAssertEqual(result, "1w ago")
    }

    // MARK: - absoluteDate tests

    /// Shared UTC timezone for deterministic absolute-date tests.
    private var utc: TimeZone { TimeZone(identifier: "UTC")! }

    func testAbsoluteDate_format() {
        let result = WindowsDateFormatting.absoluteDate(referenceDate, timeZone: utc)
        XCTAssertEqual(result, "21 May 2026")
    }

    func testAbsoluteDate_singleDigitDay() {
        var components = DateComponents()
        components.year = 2026
        components.month = 1
        components.day = 5
        components.hour = 0
        components.minute = 0
        components.second = 0
        components.timeZone = TimeZone(identifier: "UTC")
        let date = Calendar.current.date(from: components)!

        let result = WindowsDateFormatting.absoluteDate(date, timeZone: utc)
        XCTAssertEqual(result, "5 Jan 2026")
    }

    func testAbsoluteDate_december() {
        var components = DateComponents()
        components.year = 2025
        components.month = 12
        components.day = 31
        components.hour = 23
        components.minute = 59
        components.second = 59
        components.timeZone = TimeZone(identifier: "UTC")
        let date = Calendar.current.date(from: components)!

        let result = WindowsDateFormatting.absoluteDate(date, timeZone: utc)
        XCTAssertEqual(result, "31 Dec 2025")
    }

    // MARK: - absoluteDateTime tests

    func testAbsoluteDateTime_basicFormatUTC() {
        // referenceDate is 2026-05-21 12:00:00 UTC
        let result = WindowsDateFormatting.absoluteDateTime(referenceDate, timeZone: utc)
        XCTAssertEqual(result, "21 May 2026 at 12:00")
    }

    func testAbsoluteDateTime_singleDigitDayZeroPaddedMinutes() {
        var components = DateComponents()
        components.year = 2026
        components.month = 1
        components.day = 5
        components.hour = 8
        components.minute = 5
        components.second = 0
        components.timeZone = TimeZone(identifier: "UTC")
        let date = Calendar.current.date(from: components)!

        let result = WindowsDateFormatting.absoluteDateTime(date, timeZone: utc)
        XCTAssertEqual(result, "5 Jan 2026 at 08:05")
    }

    func testAbsoluteDateTime_timezoneInjectionEffect() {
        // Same date formatted with two different timezones must yield different output,
        // documenting the per-call timeZone isolation contract.
        let utcPlus5 = TimeZone(secondsFromGMT: 5 * 3600)!

        let resultUTC = WindowsDateFormatting.absoluteDateTime(referenceDate, timeZone: utc)
        let resultPlus5 = WindowsDateFormatting.absoluteDateTime(referenceDate, timeZone: utcPlus5)

        // UTC: 12:00, UTC+5: 17:00 — different formatted strings
        XCTAssertEqual(resultUTC, "21 May 2026 at 12:00")
        XCTAssertEqual(resultPlus5, "21 May 2026 at 17:00")
        XCTAssertNotEqual(resultUTC, resultPlus5,
            "Same date with different injected timezones must produce different output")
    }
}
