#if DEBUG
import Foundation
import StackCoreRust

/// Time source of a fake data session. Every seeded date is relative to `now`
/// (captured once per launch), so the data always looks fresh.
struct FakeClock: Sendable {

    let now: Date

    init(now: Date = Date()) {
        self.now = now
    }

    func date(daysAgo days: Double = 0, hoursAgo hours: Double = 0) -> Date {
        now.addingTimeInterval(-(days * 86_400 + hours * 3_600))
    }

    func date(daysFromNow days: Double) -> Date {
        now.addingTimeInterval(days * 86_400)
    }

    /// ISO 8601 string, the wire format the core hands to the app.
    func iso(daysAgo days: Double = 0, hoursAgo hours: Double = 0) -> String {
        Self.iso(date(daysAgo: days, hoursAgo: hours))
    }

    func iso(daysFromNow days: Double) -> String {
        Self.iso(date(daysFromNow: days))
    }

    static func iso(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    /// `yyyy-MM-dd` (UTC), the format of analytics processing dates.
    static func day(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

/// Lock-protected mutable state shared by every fake provider of one account,
/// so a write made on one screen (one connection) is visible on the next.
final class FakeStateBox<State>: @unchecked Sendable {

    private let lock = NSLock()
    private var state: State

    init(_ state: State) {
        self.state = state
    }

    func read<T>(_ body: (State) throws -> T) rethrows -> T {
        try lock.withLock { try body(state) }
    }

    @discardableResult
    func write<T>(_ body: (inout State) throws -> T) rethrows -> T {
        try lock.withLock { try body(&state) }
    }
}

/// Errors the fakes raise, shaped like the core's so the app's error handling
/// and translators behave as they do against the real services.
enum FakeCoreError {

    static func notFound(_ what: String) -> StackError {
        .Http(status: 404, message: "{\"errors\":[{\"status\":\"404\",\"code\":\"NOT_FOUND\",\"title\":\"The specified resource does not exist\",\"detail\":\"\(what) was not found (fake data).\"}]}")
    }

    static func invalid(_ detail: String) -> StackError {
        .Http(status: 409, message: "{\"errors\":[{\"status\":\"409\",\"code\":\"ENTITY_ERROR\",\"title\":\"The request entity is invalid\",\"detail\":\"\(detail)\"}]}")
    }

    static func unsupported(_ what: String) -> StackError {
        .Unsupported(message: "\(what) is not available in fake data mode.")
    }
}

/// The core's helpers for echoing a rejected input in a local-validation
/// message (`logging/redact.rs`: `quoted`, `shape`), so fake rejections read
/// exactly like the core's.
enum FakeCoreMessage {

    /// The core echoes at most this many characters of a rejected value.
    private static let maxEchoCharacters = 64

    /// `value` quoted like Rust's `{:?}`, cut to 64 characters (`…` marks a cut).
    static func quoted(_ value: String) -> String {
        let scalars = Array(value.unicodeScalars)
        var head = String.UnicodeScalarView()
        head.append(contentsOf: scalars.prefix(maxEchoCharacters))
        let quoted = String(reflecting: String(head))
        return scalars.count > maxEchoCharacters ? quoted + "…" : quoted
    }

    /// Length and character kinds of `value` without its content, e.g.
    /// `3 chars: letters` or `6 chars: digits, whitespace`.
    static func shape(_ value: String) -> String {
        let scalars = Array(value.unicodeScalars)
        let unit = scalars.count == 1 ? "char" : "chars"
        let isDigit: (Unicode.Scalar) -> Bool = { ("0"..."9").contains($0) }
        var kinds: [String] = []
        if scalars.contains(where: isDigit) { kinds.append("digits") }
        if scalars.contains(where: { $0.properties.isAlphabetic }) { kinds.append("letters") }
        if scalars.contains(where: { $0.properties.isWhitespace }) { kinds.append("whitespace") }
        var symbols: [Unicode.Scalar] = []
        for scalar in scalars where !isDigit(scalar) && !scalar.properties.isAlphabetic && !scalar.properties.isWhitespace {
            if !symbols.contains(scalar) { symbols.append(scalar) }
        }
        kinds += symbols.prefix(5).map(debugCharacter)
        if symbols.count > 5 { kinds.append("…") }
        return kinds.isEmpty ? "\(scalars.count) \(unit)" : "\(scalars.count) \(unit): \(kinds.joined(separator: ", "))"
    }

    /// A character quoted like Rust's `char` `{:?}` (`'@'`, `'\''`).
    private static func debugCharacter(_ scalar: Unicode.Scalar) -> String {
        switch scalar {
        case "'":  return #"'\''"#
        case "\\": return #"'\\'"#
        case "\"": return #"'"'"#
        default:
            let escaped = String(reflecting: String(scalar)).dropFirst().dropLast()
            return "'\(escaped)'"
        }
    }
}

/// Short, unique ids for records created while the app runs (`prefix-xxxxxxxx`).
enum FakeID {
    static func make(_ prefix: String) -> String {
        "\(prefix)-\(UUID().uuidString.prefix(8).lowercased())"
    }
}

/// Deterministic pseudo-random numbers (SplitMix64), so generated series
/// (analytics rows, delivery stats) are the same on every launch.
struct FakeRandom {

    private var state: UInt64

    init(seed: String) {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in seed.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100_0000_01b3
        }
        state = hash
    }

    mutating func next() -> UInt64 {
        state = state &+ 0x9e37_79b9_7f4a_7c15
        var value = state
        value = (value ^ (value >> 30)) &* 0xbf58_476d_1ce4_e5b9
        value = (value ^ (value >> 27)) &* 0x94d0_49bb_1331_11eb
        return value ^ (value >> 31)
    }

    /// Uniform in `range`.
    mutating func int(in range: ClosedRange<Int>) -> Int {
        let span = UInt64(range.upperBound - range.lowerBound + 1)
        return range.lowerBound + Int(next() % span)
    }

    /// Uniform in `0..<1`.
    mutating func unit() -> Double {
        Double(next() % 1_000_000) / 1_000_000
    }
}
#endif
