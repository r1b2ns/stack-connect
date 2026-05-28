import Foundation
import AppStoreConnect_Swift_SDK

/// Turns SDK errors and raw Apple error payloads into short, user-facing messages.
/// Falls back to Apple's `detail` field (or `error.localizedDescription`) so we
/// never hide useful info for unknown cases.
enum AppleAPIErrorTranslator {

    static func friendlyMessage(for error: Error) -> String {
        guard let providerError = error as? APIProvider.Error,
              case .requestFailure(let status, let response, _) = providerError else {
            return error.localizedDescription
        }

        let first = response?.errors?.first
        let code  = first?.code   ?? ""
        let title = first?.title  ?? ""
        let detail = first?.detail ?? ""

        if let humanized = humanize(code: code, detail: detail) {
            return humanized
        }
        if let humanized = humanize(status: status) {
            return humanized
        }

        // Last resort: use Apple's `detail` (richer than `title`), or `title` if no detail.
        if !detail.isEmpty { return detail }
        if !title.isEmpty  { return title }
        return error.localizedDescription
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
