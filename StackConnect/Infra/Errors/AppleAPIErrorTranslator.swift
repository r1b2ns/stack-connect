import Foundation
import StackCoreRust

/// Turns core errors and raw Apple error payloads into short, user-facing messages.
/// Falls back to Apple's `detail` field (or `error.localizedDescription`) so we
/// never hide useful info for unknown cases.
enum AppleAPIErrorTranslator {

    // MARK: - Raw Apple error payload (JSON:API error document)

    private struct AppleErrorPayload: Decodable {
        let errors: [AppleErrorItem]?
    }

    private struct AppleErrorItem: Decodable {
        let status: String?
        let code: String?
        let title: String?
        let detail: String?
        let meta: Meta?

        /// Nested error metadata. Apple hangs the *real* cause of some 409s under
        /// `meta.associatedErrors`, keyed by the resource path
        /// (e.g. `"/apps/1561937578"`), with the top-level error being a generic
        /// `STATE_ERROR.ENTITY_STATE_INVALID`.
        struct Meta: Decodable {
            let associatedErrors: [String: [AppleErrorItem]]?
        }
    }

    /// Decodes the raw App Store Connect response body and returns the first error,
    /// or `nil` on any decode failure or an empty `errors` array.
    private static func firstError(fromBody body: String) -> AppleErrorItem? {
        guard let data = body.data(using: .utf8),
              let payload = try? JSONDecoder().decode(AppleErrorPayload.self, from: data),
              let first = payload.errors?.first else {
            return nil
        }
        return first
    }

    /// Internal helper so callers (e.g. `SyncService`) can decode the body without
    /// duplicating the private payload structs. Returns `nil` if there is no first error.
    static func decodeFirstError(
        fromBody body: String
    ) -> (code: String?, title: String?, detail: String?, status: String?)? {
        guard let first = firstError(fromBody: body) else { return nil }
        return (first.code, first.title, first.detail, first.status)
    }

    static func friendlyMessage(for error: Error) -> String {
        guard case StackCoreRust.StackError.Http(let status, let message) = error else {
            return error.localizedDescription
        }

        let first = firstError(fromBody: message)
        let code   = first?.code   ?? ""
        let title  = first?.title  ?? ""
        let detail = first?.detail ?? ""

        // Nested `meta.associatedErrors` often carry the real cause (e.g. the
        // concurrent-submission limit) while the top-level code is a generic
        // `ENTITY_STATE_INVALID`. Scan every code — top-level and nested — so
        // those get humanized too. The concurrency case is checked first because
        // it has a dedicated, actionable message.
        let allCodes = allErrorCodes(fromBody: message)
        if allCodes.contains(concurrentSubmissionLimitCode) {
            return String(localized: "You've reached Apple's limit of 5 review submissions in progress for this app. Cancel or submit an existing one before starting a new review.")
        }

        if let humanized = humanize(code: code, detail: detail) {
            return humanized
        }
        for nestedCode in allCodes where nestedCode != code {
            if let humanized = humanize(code: nestedCode, detail: detail) {
                return humanized
            }
        }
        if let humanized = humanize(status: Int(status)) {
            return humanized
        }

        // Last resort: use Apple's `detail` (richer than `title`), or `title` if no detail.
        if !detail.isEmpty { return detail }
        if !title.isEmpty  { return title }
        return error.localizedDescription
    }

    // MARK: - Pending agreements detection

    /// Likely ASC error codes for a missing/expired account agreement on a 403.
    // TODO(#73): confirm exact ASC error code against a live 403 response and pin it.
    private static let pendingAgreementCodes: Set<String> = [
        "FORBIDDEN.REQUIRED_AGREEMENTS_MISSING_OR_EXPIRED",
        "FORBIDDEN_REQUIRED_AGREEMENTS_MISSING_OR_EXPIRED"
    ]

    private static let agreementRegex = try? NSRegularExpression(pattern: "agreement", options: .caseInsensitive)

    /// Detects, indirectly, that Apple is blocking ASC calls for an account
    /// because of pending or updated account agreements (Paid Apps / Program
    /// License Agreement). Apple has no agreements API, so the only signal is a
    /// 403 whose error payload references agreements.
    static func isPendingAgreement(_ error: Error) -> Bool {
        // Rust-core path: the core surfaces a typed pending-agreements error.
        if case StackCoreRust.StackError.PendingAgreements = error {
            return true
        }

        // Defensive fallback: classify a raw 403 whose payload references agreements.
        guard case StackCoreRust.StackError.Http(let status, let message) = error,
              status == 403 else {
            return false
        }

        let decoded = decodeFirstError(fromBody: message)
        let code = (decoded?.code ?? "").uppercased()
        let detail = decoded?.detail ?? ""
        let title = decoded?.title ?? ""

        // Primary match: a known agreement error code.
        if pendingAgreementCodes.contains(code) {
            return true
        }

        // Defensive fallback: any "agreement" mention in the payload.
        let haystack = "\(code) \(detail) \(title)".lowercased()
        if let agreementRegex {
            let range = NSRange(haystack.startIndex..., in: haystack)
            if agreementRegex.firstMatch(in: haystack, range: range) != nil {
                return true
            }
        }

        return false
    }

    // MARK: - Forbidden detection

    /// True when Apple rejected the request with a 403 `FORBIDDEN_ERROR`.
    /// For Users & Access operations this almost always means the API key lacks
    /// the Admin role required to create or remove users.
    static func isForbidden(_ error: Error) -> Bool {
        guard case StackCoreRust.StackError.Http(let status, let message) = error,
              status == 403 else {
            return false
        }
        let code = (decodeFirstError(fromBody: message)?.code ?? "").uppercased()
        return code == "FORBIDDEN_ERROR"
    }

    // MARK: - Concurrent review-submission limit (the 409 root cause)

    /// The ASC error code Apple returns — nested under `meta.associatedErrors` —
    /// once an app already has 5 unfinished review submissions.
    private static let concurrentSubmissionLimitCode = "STATE_ERROR.CONCURRENT_REVIEW_SUBMISSION_LIMIT_EXCEEDED"

    /// True when a "Submit for review" call failed because the app already has
    /// Apple's maximum of 5 concurrent (unfinished) review submissions.
    ///
    /// The top-level error is a generic `STATE_ERROR.ENTITY_STATE_INVALID`; the
    /// specific code lives under `meta.associatedErrors`. We check both the
    /// top-level code (defensive, in case Apple ever surfaces it directly) and
    /// every nested associated error, then fall back to a raw string match.
    static func isConcurrentSubmissionLimit(_ error: Error) -> Bool {
        guard case StackCoreRust.StackError.Http(let status, let message) = error,
              status == 409 else {
            return false
        }

        if allErrorCodes(fromBody: message).contains(concurrentSubmissionLimitCode) {
            return true
        }

        // Defensive fallback: the code can appear even if the JSON shape shifts.
        return message.contains(concurrentSubmissionLimitCode)
    }

    /// Collects the top-level error code plus every `meta.associatedErrors` code
    /// from a raw ASC error body. Empty on decode failure.
    private static func allErrorCodes(fromBody body: String) -> Set<String> {
        guard let data = body.data(using: .utf8),
              let payload = try? JSONDecoder().decode(AppleErrorPayload.self, from: data),
              let errors = payload.errors else {
            return []
        }

        var codes = Set<String>()
        for error in errors {
            if let code = error.code {
                codes.insert(code)
            }
            for nested in error.meta?.associatedErrors?.values.flatMap({ $0 }) ?? [] {
                if let code = nested.code {
                    codes.insert(code)
                }
            }
        }
        return codes
    }

    // MARK: - Pattern matching

    private static func humanize(code: String, detail: String) -> String? {
        let lower = detail.lowercased()

        if lower.contains("does not allow changes to the 'in-app purchase'") ||
           lower.contains("does not allow changes to the 'inapppurchase'") {
            return String(localized: "In-App Purchase is enabled by default on every Bundle ID and cannot be removed.")
        }

        if lower.contains("does not allow changes to the") {
            if let feature = extractQuotedFeature(from: detail) {
                return String(localized: "Apple does not allow the “\(feature)” capability to be modified on this Bundle ID. It may be required, or it might only be changeable on developer.apple.com.")
            }
            return String(localized: "Apple does not allow this capability to be modified on this Bundle ID. It may be required, or only changeable on developer.apple.com.")
        }

        if lower.contains("game center") && lower.contains("required") {
            return String(localized: "Game Center is required for this Bundle ID and cannot be removed.")
        }

        // Profile-creation mismatch: selected certs/devices don't match the profile type.
        if lower.contains("no current certificates") && lower.contains("compatible with") {
            let profileType = extractTrailingProfileType(from: detail)
            if let profileType {
                return String(localized: "None of the selected certificates are compatible with \(profileType) profiles. Pick a development certificate for development profiles, or a distribution certificate otherwise — and make sure the platform matches (iOS certs for iOS/tvOS/Mac Catalyst, Mac certs for macOS).")
            }
            return String(localized: "None of the selected certificates are compatible with this profile type. Pick a development certificate for development profiles, or a distribution certificate otherwise.")
        }
        if lower.contains("no current devices") && lower.contains("compatible with") {
            return String(localized: "None of the selected devices are compatible with this profile type. Make sure they match the profile's platform (iOS devices for iOS profiles, Mac devices for macOS).")
        }
        if lower.contains("must have at least one device") {
            return String(localized: "Development and Ad Hoc profiles must include at least one device.")
        }
        if lower.contains("must have at least one certificate") {
            return String(localized: "Profiles must include at least one certificate.")
        }
        if lower.contains("bundle id") && lower.contains("does not match") {
            return String(localized: "The selected Bundle ID's platform does not match the profile type you chose.")
        }
        if lower.contains("name") && lower.contains("already") && lower.contains("exists") {
            return String(localized: "A profile with this name already exists. Pick a different name.")
        }

        switch code {
        case "FORBIDDEN_ERROR":
            return String(localized: "Apple refused this change for security reasons. The operation may only be available on developer.apple.com.")
        case "ENTITY_ERROR.NAME.INVALID":
            return String(localized: "Apple doesn't accept this name. Try a shorter or simpler value, without special characters.")
        case "ENTITY_ERROR.NAME.TOO_LONG":
            return String(localized: "The name is too long for Apple to accept.")
        case "ENTITY_ERROR.ATTRIBUTE.REQUIRED":
            return String(localized: "A required field is missing.")
        case "ENTITY_ERROR.ATTRIBUTE.INVALID":
            return detail.isEmpty
                ? String(localized: "One of the fields has an invalid value.")
                : detail
        case "ENTITY_ERROR.RELATIONSHIP.INVALID":
            return String(localized: "A required relationship is missing or invalid (for example, the Pass Type ID or Merchant ID).")
        case "CONFLICT_ERROR":
            return String(localized: "An item with the same value already exists.")
        case "PARAMETER_ERROR.ILLEGAL":
            return detail.isEmpty
                ? String(localized: "A parameter sent to Apple is not allowed for this request.")
                : detail
        case "NOT_FOUND":
            return String(localized: "The resource was not found — it may have already been deleted.")
        case "UNAUTHORIZED":
            return String(localized: "Your API key was rejected by Apple. Re-validate the account and try again.")
        case "INTERNAL_ERROR", "INTERNAL_SERVER_ERROR":
            return String(localized: "Apple's service is temporarily unavailable. Try again in a few minutes.")
        default:
            return nil
        }
    }

    private static func humanize(status: Int) -> String? {
        switch status {
        case 401:
            return String(localized: "Your API key was rejected by Apple. Re-validate the account and try again.")
        case 403:
            return String(localized: "Apple refused this change for security reasons.")
        case 404:
            return String(localized: "Resource not found — it may have already been deleted.")
        case 409:
            return String(localized: "Conflict: an item with the same value already exists.")
        case 429:
            return String(localized: "You hit Apple's rate limit. Wait a moment and try again.")
        case 500...599:
            return String(localized: "Apple's service is temporarily unavailable. Try again in a few minutes.")
        default:
            return nil
        }
    }

    private static func extractQuotedFeature(from detail: String) -> String? {
        let pattern = #"does not allow changes to the '([^']+)' feature"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: detail, range: NSRange(detail.startIndex..., in: detail)),
              let range = Range(match.range(at: 1), in: detail) else {
            return nil
        }
        return String(detail[range])
    }

    /// Pulls a raw profile type identifier (e.g. `IOS_APP_DEVELOPMENT`) from a sentence and
    /// returns a friendlier display name.
    private static func extractTrailingProfileType(from detail: String) -> String? {
        let pattern = #"compatible with ([A-Z_]+) profiles"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: detail, range: NSRange(detail.startIndex..., in: detail)),
              let range = Range(match.range(at: 1), in: detail) else {
            return nil
        }
        let raw = String(detail[range])
        return prettifyProfileType(raw)
    }

    private static func prettifyProfileType(_ raw: String) -> String {
        switch raw {
        case "IOS_APP_DEVELOPMENT":          return "iOS App Development"
        case "IOS_APP_STORE":                return "iOS App Store"
        case "IOS_APP_ADHOC":                return "iOS Ad Hoc"
        case "IOS_APP_INHOUSE":              return "iOS In-House"
        case "MAC_APP_DEVELOPMENT":          return "Mac Development"
        case "MAC_APP_STORE":                return "Mac App Store"
        case "MAC_APP_DIRECT":               return "Mac Direct"
        case "TVOS_APP_DEVELOPMENT":         return "tvOS App Development"
        case "TVOS_APP_STORE":               return "tvOS App Store"
        case "TVOS_APP_ADHOC":               return "tvOS Ad Hoc"
        case "TVOS_APP_INHOUSE":             return "tvOS In-House"
        case "MAC_CATALYST_APP_DEVELOPMENT": return "Mac Catalyst Development"
        case "MAC_CATALYST_APP_STORE":       return "Mac Catalyst App Store"
        case "MAC_CATALYST_APP_DIRECT":      return "Mac Catalyst Direct"
        default:
            return raw
                .split(separator: "_")
                .map { $0.capitalized }
                .joined(separator: " ")
        }
    }
}
