import Foundation
import StackCoreRust
import APIProviderFirebase

// MARK: - User-facing error

/// An error as a screen shows it: a short title and, when there is more to
/// say, a detail line.
///
/// Built by `UserFacingErrorMapper` from any `Error`. Never carries JSON,
/// escape sequences or Swift type names: server bodies are parsed, and what
/// can't be read falls back to localized copy.
struct UserFacingError: Equatable, Sendable {

    let title: String
    let detail: String?

    init(title: String, detail: String? = nil) {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDetail = detail?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.title = trimmedTitle
        // A detail repeating the title adds nothing.
        if let trimmedDetail, !trimmedDetail.isEmpty, trimmedDetail != trimmedTitle {
            self.detail = trimmedDetail
        } else {
            self.detail = nil
        }
    }

    /// Title and detail as one text, for screens with a single text slot
    /// (alerts, inline errors, empty-state descriptions): "Title. Detail".
    var message: String {
        guard let detail else { return title }
        guard !title.isEmpty else { return detail }
        let separator = Self.endsWithPunctuation(title) ? " " : ". "
        return title + separator + detail
    }

    private static let sentenceEndings: Set<Character> = [".", "!", "?", ":", "。", "！", "？", "：", "…"]

    private static func endsWithPunctuation(_ text: String) -> Bool {
        guard let last = text.last else { return false }
        return sentenceEndings.contains(last)
    }
}

// MARK: - Mapper

/// The single place that turns any error into what the user reads.
///
/// Order of precedence:
/// 1. Errors that already carry ready-to-show copy (`OfflineError`, Apple ID
///    session expiry, a review submission that can't be removed).
/// 2. `StackError` from the Rust core: its server message is parsed —
///    App Store Connect `{"errors":[{title, detail}]}`, Google APIs
///    `{"error":{message, errors}}`, OAuth `{"error", "error_description"}` —
///    plain text is shown trimmed, and an empty or unreadable body falls back
///    to localized copy by HTTP status.
/// 3. Firebase REST errors (`APIProviderFirebase.Error`, `FirebaseAuthError`),
///    whose own descriptions embed URLs and raw bodies.
/// 4. Anything else: its `localizedDescription`.
///
/// Screen-specific translators (`AppleAPIErrorTranslator`,
/// `GooglePlayErrorTranslator`, the sign-in flows) still run first where a
/// screen uses them; they fall back here.
enum UserFacingErrorMapper {

    static func map(_ error: Error) -> UserFacingError {
        if let offline = error as? OfflineError {
            return UserFacingError(title: offline.localizedDescription)
        }
        if let stackError = error as? StackError {
            return map(stackError)
        }
        if let firebaseError = error as? APIProviderFirebase.Error {
            return map(firebaseError)
        }
        if let authError = error as? FirebaseAuthError {
            return map(authError)
        }
        return UserFacingError(title: error.localizedDescription)
    }

    // MARK: StackError

    static func map(_ error: StackError) -> UserFacingError {
        switch error {
        case .SessionExpired:
            return UserFacingError(title: AppleAPIErrorTranslator.sessionExpiredMessage)

        case .SubmissionNotRemovable(let message):
            // The core's message is ready to show (see `AppleAPIErrorTranslator`).
            return fromServerMessage(message, lead: Copy.submissionNotRemovable)

        case .Http(let status, let message):
            return fromServerMessage(message, fallback: Copy.httpStatus(Int(status)))

        case .InvalidCredentials(let message):
            return fromServerMessage(message, lead: Copy.invalidCredentials)

        case .Auth(let message):
            return fromServerMessage(message, lead: Copy.accessDenied)

        case .PendingAgreements(let message):
            return fromServerMessage(message, lead: Copy.pendingAgreements)

        case .Unsupported(let message):
            return fromServerMessage(message, lead: Copy.unsupported)

        case .ReleaseNotFound:
            return UserFacingError(title: Copy.releaseNotFound)

        case .Network:
            // reqwest's transport text names hosts and internals: not for users.
            return UserFacingError(title: Copy.network)

        case .Decode:
            // A serde message about the payload's shape: not for users.
            return UserFacingError(title: Copy.unexpectedResponse)
        }
    }

    // MARK: Firebase

    private static func map(_ error: APIProviderFirebase.Error) -> UserFacingError {
        switch error {
        case .requestFailure(let status, let response, _):
            let googleError = response?.error
            if let message = googleError?.message?.trimmingCharacters(in: .whitespacesAndNewlines), !message.isEmpty {
                let extra = distinct((googleError?.errors ?? []).compactMap(\.message), excluding: message)
                return UserFacingError(title: message, detail: extra.joined(separator: "\n"))
            }
            return UserFacingError(title: Copy.httpStatus(status))
        case .decodingError, .unknownResponseType:
            return UserFacingError(title: Copy.unexpectedResponse)
        case .requestGeneration:
            return UserFacingError(title: Copy.generic)
        case .requestExecutorError(let underlying):
            if underlying is URLError {
                return UserFacingError(title: Copy.network)
            }
            return map(underlying)
        }
    }

    private static func map(_ error: FirebaseAuthError) -> UserFacingError {
        switch error {
        case .tokenExchangeFailed(let status, let body):
            return fromServerMessage(body ?? "", fallback: Copy.httpStatus(status))
        default:
            return UserFacingError(title: error.localizedDescription)
        }
    }

    // MARK: Server messages

    /// A core message used as the whole error: parsed title + detail, or the
    /// trimmed text, or `fallback` when there's nothing readable.
    private static func fromServerMessage(_ message: String, fallback: String) -> UserFacingError {
        guard let parsed = ServerErrorBody.parse(message) else {
            return UserFacingError(title: fallback)
        }
        return parsed
    }

    /// A core message shown under a localized `lead`: a parsed JSON body
    /// replaces the lead (the server's own title is more precise); plain text
    /// becomes the detail.
    private static func fromServerMessage(_ message: String, lead: String) -> UserFacingError {
        switch ServerErrorBody.read(message) {
        case .structured(let parsed):
            return parsed
        case .plainText(let text):
            return UserFacingError(title: lead, detail: text)
        case .unreadable:
            return UserFacingError(title: lead)
        }
    }

    static func distinct(_ values: [String], excluding excluded: String? = nil) -> [String] {
        var seen = Set<String>()
        if let excluded { seen.insert(excluded) }
        var result: [String] = []
        for value in values {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed).inserted else { continue }
            result.append(trimmed)
        }
        return result
    }

    // MARK: Copy

    enum Copy {

        static var generic: String {
            String(localized: "Something went wrong. Try again.",
                   comment: "Generic error shown when nothing more specific is known about a failure.")
        }

        static var network: String {
            String(localized: "Couldn't reach the server. Check your internet connection and try again.",
                   comment: "Error shown when a request couldn't be sent or its answer couldn't be read (no network, timeout).")
        }

        static var unexpectedResponse: String {
            String(localized: "The server returned an unexpected response. Try again later.",
                   comment: "Error shown when App Store Connect, Google Play or Firebase answers with data the app can't read.")
        }

        static var invalidCredentials: String {
            String(localized: "The account's credentials were rejected. Check them and try again.",
                   comment: "Error lead shown when the API key, key file or sign-in of an account is not accepted. May be followed by the server's own explanation.")
        }

        static var accessDenied: String {
            String(localized: "Access was denied.",
                   comment: "Error lead shown when the server refuses the account's access. Followed by the server's own explanation when there is one.")
        }

        static var pendingAgreements: String {
            String(localized: "App Store Connect has agreements waiting to be accepted by the Account Holder. Some data may not sync until then.")
        }

        static var unsupported: String {
            String(localized: "This action isn't supported.",
                   comment: "Error lead shown when the service has no way to perform the requested action. May be followed by the reason.")
        }

        static var submissionNotRemovable: String {
            String(localized: "This review submission can't be removed through the App Store Connect API.",
                   comment: "Error shown when an empty App Store review submission can't be deleted through Apple's API (only on the App Store Connect website).")
        }

        static var releaseNotFound: String {
            String(localized: "This release changed on Google Play since it was loaded. Refresh and try again.")
        }

        /// Localized copy for an HTTP status whose body says nothing readable.
        static func httpStatus(_ status: Int) -> String {
            switch status {
            case 401:
                return String(localized: "The server didn't accept the account's credentials. Check the account and try again.",
                              comment: "Error for an HTTP 401 answer without a readable explanation.")
            case 403:
                return String(localized: "You don't have permission to do this.",
                              comment: "Error for an HTTP 403 answer without a readable explanation.")
            case 404:
                return String(localized: "The item wasn't found. It may have been deleted.",
                              comment: "Error for an HTTP 404 answer without a readable explanation.")
            case 409:
                return String(localized: "This change conflicts with the item's current state. Refresh and try again.",
                              comment: "Error for an HTTP 409 answer without a readable explanation.")
            case 429:
                return String(localized: "Too many requests. Wait a moment and try again.",
                              comment: "Error for an HTTP 429 (rate limit) answer without a readable explanation.")
            case 500...599:
                return String(localized: "The service is temporarily unavailable. Try again in a few minutes.",
                              comment: "Error for an HTTP 5xx answer without a readable explanation.")
            default:
                return String(localized: "The request failed (HTTP \(status)).",
                              comment: "Error for an HTTP error answer without a readable explanation. The placeholder is the HTTP status code.")
            }
        }
    }
}

// MARK: - Server error bodies

/// Reads the error bodies App Store Connect, Google APIs and OAuth servers
/// answer with, as the core passes them in `StackError` messages.
enum ServerErrorBody {

    enum Reading: Equatable {
        /// A recognized JSON error document.
        case structured(UserFacingError)
        /// Text that isn't JSON, trimmed.
        case plainText(String)
        /// Empty, malformed JSON, JSON of an unknown shape, or HTML.
        case unreadable
    }

    /// Longest plain-text body shown as is; longer ones are cut.
    static let maxPlainTextLength = 600

    /// Title + detail of a recognized JSON body, or the trimmed plain text as
    /// the title. `nil` when nothing in `body` is fit to show.
    static func parse(_ body: String) -> UserFacingError? {
        switch read(body) {
        case .structured(let error): return error
        case .plainText(let text):   return UserFacingError(title: text)
        case .unreadable:            return nil
        }
    }

    /// The body as one readable text (`UserFacingError.message`), `nil` when
    /// nothing in it is fit to show. For translators that append the server's
    /// own words after their lead sentence.
    static func readableText(_ body: String) -> String? {
        parse(body)?.message
    }

    static func read(_ body: String) -> Reading {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .unreadable }

        if let jsonStart = trimmed.firstIndex(where: { $0 == "{" || $0 == "[" }) {
            // The core sometimes prefixes the body ("HTTP 403: {…}"): read the
            // JSON from its first brace.
            let candidate = String(trimmed[jsonStart...])
            if let object = jsonObject(candidate) {
                if let parsed = structured(from: object) {
                    return .structured(parsed)
                }
                return .unreadable
            }
            if jsonStart == trimmed.startIndex || candidate.contains("\":") {
                // Looks like JSON but isn't valid JSON: never show it.
                return .unreadable
            }
        }

        let lowered = trimmed.lowercased()
        if lowered.hasPrefix("<!doctype") || lowered.hasPrefix("<html") || lowered.contains("<body") {
            return .unreadable
        }
        if trimmed.count > maxPlainTextLength {
            return .plainText(String(trimmed.prefix(maxPlainTextLength)) + "…")
        }
        return .plainText(trimmed)
    }

    // MARK: Private

    private static func jsonObject(_ text: String) -> Any? {
        guard let data = text.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    }

    private static func structured(from object: Any) -> UserFacingError? {
        // A bare array of JSON:API errors.
        if let array = object as? [[String: Any]] {
            return appStoreConnect(errors: array)
        }
        guard let dictionary = object as? [String: Any] else { return nil }

        // App Store Connect (JSON:API): {"errors": [{"title", "detail", …}]}
        if let errors = dictionary["errors"] as? [[String: Any]], let parsed = appStoreConnect(errors: errors) {
            return parsed
        }
        // Google APIs: {"error": {"code", "message", "status", "errors": [{"message"}]}}
        if let googleError = dictionary["error"] as? [String: Any], let parsed = google(error: googleError) {
            return parsed
        }
        // OAuth (Google / Firebase token endpoints): {"error": "…", "error_description": "…"}
        if let code = dictionary["error"] as? String {
            return oauth(code: code, description: dictionary["error_description"] as? String)
        }
        // Anything else with a top-level human message.
        if let message = nonEmptyString(dictionary["message"]) {
            return UserFacingError(title: message, detail: nonEmptyString(dictionary["detail"]))
        }
        return nil
    }

    private static func appStoreConnect(errors: [[String: Any]]) -> UserFacingError? {
        let items: [(title: String?, detail: String?)] = errors.map {
            (nonEmptyString($0["title"]), nonEmptyString($0["detail"]))
        }.filter { $0.title != nil || $0.detail != nil }
        guard let first = items.first else { return nil }

        guard let title = first.title else {
            // No title: the first detail leads, the others follow.
            let details = UserFacingErrorMapper.distinct(items.compactMap { $0.detail ?? $0.title })
            return UserFacingError(title: details.first ?? "", detail: details.dropFirst().joined(separator: "\n"))
        }
        // Every distinct line after the first title: each item's detail, or its
        // title when it has none and differs from the first.
        let lines = items.compactMap { item in item.detail ?? item.title }
        let details = UserFacingErrorMapper.distinct(lines, excluding: title)
        return UserFacingError(title: title, detail: details.joined(separator: "\n"))
    }

    private static func google(error: [String: Any]) -> UserFacingError? {
        let nested = (error["errors"] as? [[String: Any]] ?? []).compactMap { nonEmptyString($0["message"]) }
        if let message = nonEmptyString(error["message"]) {
            let extra = UserFacingErrorMapper.distinct(nested, excluding: message)
            return UserFacingError(title: message, detail: extra.joined(separator: "\n"))
        }
        let messages = UserFacingErrorMapper.distinct(nested)
        guard let first = messages.first else { return nil }
        return UserFacingError(title: first, detail: messages.dropFirst().joined(separator: "\n"))
    }

    private static func oauth(code: String, description: String?) -> UserFacingError? {
        if let description = nonEmptyString(description) {
            return UserFacingError(title: description)
        }
        let trimmedCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCode.isEmpty else { return nil }
        // "invalid_grant" → "Invalid grant"
        let words = trimmedCode.replacingOccurrences(of: "_", with: " ")
        return UserFacingError(title: words.prefix(1).uppercased() + words.dropFirst())
    }

    private static func nonEmptyString(_ value: Any?) -> String? {
        guard let string = value as? String else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

// MARK: - Conveniences

extension Error {

    /// This error as a screen shows it (`UserFacingErrorMapper`).
    var userFacing: UserFacingError {
        UserFacingErrorMapper.map(self)
    }

    /// This error as one user-facing text ("Title. Detail"). Use it instead of
    /// `localizedDescription`, which for a core `StackError` is a debug dump:
    /// UniFFI generates `StackError`'s `LocalizedError` conformance
    /// (`errorDescription` = `String(reflecting: self)`) in the
    /// `StackCoreRust` module, and its witnesses can't be replaced from here.
    var userFacingMessage: String {
        UserFacingErrorMapper.map(self).message
    }
}
