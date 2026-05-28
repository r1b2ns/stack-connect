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
}
