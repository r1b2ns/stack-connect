import Foundation
import StackProtocols

/// The pure part of `FirebaseAnalyticsProvider`: turns an `AnalyticsEvent` into
/// what `Analytics.logEvent` accepts, enforcing Firebase's limits. Kept free of
/// any Firebase import so it is unit tested without a configured `FirebaseApp`.
///
/// Anything out of bounds is truncated or dropped (and logged), never trapped:
/// a bad parameter must not cost the whole event, let alone a crash.
struct FirebaseAnalyticsPayload: Equatable {
    let name: String
    /// Values are `NSString` or `NSNumber` only.
    let parameters: [String: NSObject]

    // MARK: - Firebase limits

    static let maxEventNameLength = 40
    static let maxParameterNameLength = 40
    static let maxStringValueLength = 100
    static let maxParameterCount = 25

    /// Prefixes Firebase reserves for event and parameter names.
    static let reservedPrefixes = ["firebase_", "google_", "ga_"]

    /// Event names Firebase logs automatically and rejects from apps.
    static let reservedEventNames: Set<String> = [
        "ad_activeview", "ad_click", "ad_exposure", "ad_impression", "ad_query",
        "ad_reward", "adunit_exposure", "app_background", "app_clear_data",
        "app_exception", "app_remove", "app_store_refund",
        "app_store_subscription_cancel", "app_store_subscription_convert",
        "app_store_subscription_renew", "app_upgrade", "app_update",
        "dynamic_link_app_open", "dynamic_link_app_update", "dynamic_link_first_open",
        "error", "first_open", "first_visit", "in_app_purchase",
        "notification_dismiss", "notification_foreground", "notification_open",
        "notification_receive", "os_update", "session_start",
        "session_start_with_rollout", "user_engagement"
    ]

    // MARK: - Mapping

    /// Builds the payload for `event`, or `nil` when the event name itself is
    /// unusable (reserved, empty or not `[A-Za-z][A-Za-z0-9_]*`).
    ///
    /// - `screen_view` / `screen_name` already match Firebase's
    ///   `AnalyticsEventScreenView` / `AnalyticsParameterScreenName`, so names
    ///   pass through unchanged.
    /// - Too-long names are truncated to 40 characters.
    /// - Parameters with an invalid or reserved name, or a non-finite double, are
    ///   dropped. String values are truncated to 100 characters.
    /// - Booleans are sent as `"true"` / `"false"`: GA4 custom dimensions are
    ///   text, and an `NSNumber` bool would arrive as an indistinguishable 1/0.
    /// - Above 25 parameters, the first 25 by sorted key are kept.
    static func make(from event: AnalyticsEvent) -> FirebaseAnalyticsPayload? {
        guard let name = sanitizedEventName(event.name) else {
            Log.print.warning("[Analytics][Firebase] Dropped event with unusable name '\(event.name)'")
            return nil
        }

        var parameters: [String: NSObject] = [:]
        for key in event.parameters.keys.sorted() {
            guard let value = event.parameters[key] else { continue }
            guard let sanitizedKey = sanitizedParameterName(key) else {
                Log.print.warning("[Analytics][Firebase] Dropped parameter '\(key)' on '\(name)': unusable name")
                continue
            }
            guard let object = firebaseValue(value, key: sanitizedKey, event: name) else { continue }
            guard parameters[sanitizedKey] == nil else {
                // Two long keys truncated to the same 40 characters: keep the first.
                Log.print.warning("[Analytics][Firebase] Dropped parameter '\(key)' on '\(name)': duplicate after truncation")
                continue
            }
            guard parameters.count < maxParameterCount else {
                Log.print.warning("[Analytics][Firebase] Dropped parameter '\(key)' on '\(name)': over \(maxParameterCount) parameters")
                continue
            }
            parameters[sanitizedKey] = object
        }

        return FirebaseAnalyticsPayload(name: name, parameters: parameters)
    }

    // MARK: - Private

    private static func sanitizedEventName(_ raw: String) -> String? {
        guard let name = sanitizedName(raw, maxLength: maxEventNameLength) else { return nil }
        guard !reservedEventNames.contains(name) else { return nil }
        return name
    }

    private static func sanitizedParameterName(_ raw: String) -> String? {
        sanitizedName(raw, maxLength: maxParameterNameLength)
    }

    /// Shared rules for event and parameter names: `[A-Za-z][A-Za-z0-9_]*`, no
    /// reserved prefix, truncated to `maxLength`.
    private static func sanitizedName(_ raw: String, maxLength: Int) -> String? {
        guard let first = raw.unicodeScalars.first,
              first.isASCII, CharacterSet.letters.contains(first) else { return nil }
        let isValid = raw.unicodeScalars.allSatisfy { scalar in
            scalar.isASCII && (CharacterSet.alphanumerics.contains(scalar) || scalar == "_")
        }
        guard isValid else { return nil }
        let lowercased = raw.lowercased()
        guard !reservedPrefixes.contains(where: { lowercased.hasPrefix($0) }) else { return nil }

        guard raw.count > maxLength else { return raw }
        Log.print.warning("[Analytics][Firebase] Truncated name '\(raw)' to \(maxLength) characters")
        return String(raw.prefix(maxLength))
    }

    private static func firebaseValue(_ value: AnalyticsValue, key: String, event: String) -> NSObject? {
        switch value {
        case .string(let string):
            guard string.count > maxStringValueLength else { return string as NSString }
            Log.print.warning("[Analytics][Firebase] Truncated value of '\(key)' on '\(event)' to \(maxStringValueLength) characters")
            return String(string.prefix(maxStringValueLength)) as NSString
        case .int(let int):
            return NSNumber(value: Int64(int))
        case .double(let double):
            guard double.isFinite else {
                Log.print.warning("[Analytics][Firebase] Dropped non-finite value of '\(key)' on '\(event)'")
                return nil
            }
            return NSNumber(value: double)
        case .bool(let bool):
            return (bool ? "true" : "false") as NSString
        }
    }
}
