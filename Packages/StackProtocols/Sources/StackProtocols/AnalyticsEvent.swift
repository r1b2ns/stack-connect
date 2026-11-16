import Foundation

/// A single, provider-agnostic analytics event.
///
/// `name` is snake_case (e.g. `screen_view`). Parameters are restricted to
/// `AnalyticsValue` so payloads stay PII-safe and `Sendable`: call sites build
/// events through typed factories in the app, never from free-form objects.
public struct AnalyticsEvent: Equatable, Sendable {
    public let name: String
    public let parameters: [String: AnalyticsValue]

    public init(name: String, parameters: [String: AnalyticsValue] = [:]) {
        self.name = name
        self.parameters = parameters
    }
}

/// The only value types an analytics parameter may carry.
public enum AnalyticsValue: Equatable, Sendable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)

    /// Plain textual form, used by log-based providers.
    public var stringValue: String {
        switch self {
        case .string(let value): return value
        case .int(let value): return String(value)
        case .double(let value): return String(value)
        case .bool(let value): return String(value)
        }
    }
}
