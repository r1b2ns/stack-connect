import Foundation
import StackCoreRust

// MARK: - Users call

/// One call to a Google Play developer account's users (`developers.users…`),
/// as far as an error report and the log need it: which method, on which
/// resource, with which developer ID and as which service account.
///
/// Holds no secret: the developer ID is in every Play Console URL, and the
/// service account e-mail (`client_email`) is the public identifier a Play
/// Console admin grants permissions to.
struct GooglePlayUsersCall: Equatable, Sendable {

    /// The Play Developer API method, named as Google documents it.
    enum Method: String, Sendable {
        case list = "developers.users.list"
        case invite = "developers.users.create"
        case update = "developers.users.patch"
        case delete = "developers.users.delete"
        /// The core patches the grant and creates it when Google has none yet.
        case setGrant = "developers.users.grants.patch"
        case deleteGrant = "developers.users.grants.delete"
    }

    let method: Method
    /// The developer ID exactly as stored on the account (not re-normalized),
    /// so a report shows what was really sent.
    let developerId: String
    /// The user a change addresses (part of the resource path).
    var email: String?
    /// The app a grant call addresses (part of the resource path).
    var packageName: String?
    /// The calling service account's `client_email`, `nil` when the key can't
    /// be read.
    var serviceAccountEmail: String?

    init(
        _ method: Method,
        developerId: String,
        email: String? = nil,
        packageName: String? = nil,
        serviceAccountEmail: String? = nil
    ) {
        self.method = method
        self.developerId = developerId
        self.email = email
        self.packageName = packageName
        self.serviceAccountEmail = serviceAccountEmail
    }

    /// How `GooglePlayErrorTranslator` reads this call's statuses.
    var operation: GooglePlayErrorTranslator.Operation {
        switch self.method {
        case .list:                                       return .users
        case .invite:                                     return .inviteUser
        case .update, .delete, .setGrant, .deleteGrant:   return .userChange
        }
    }

    /// `developers/{id}/users[/{email}[/grants/{package}]]`, the path the core
    /// calls under `androidpublisher/v3/`.
    var resourcePath: String {
        var path = "developers/\(developerId)/users"
        switch self.method {
        case .list, .invite:
            return path
        case .update, .delete:
            if let email { path += "/\(email)" }
            return path
        case .setGrant, .deleteGrant:
            if let email { path += "/\(email)" }
            if let packageName { path += "/grants/\(packageName)" }
            return path
        }
    }
}

// MARK: - Error details

/// Technical facts about a failed Google Play call, for the "Technical
/// details" section of a shared error report (`ErrorReportContext`) and for
/// the log: the operation, the error kind, the HTTP status, the core's (or
/// Google's) message verbatim and where the error came from. For a users call
/// it also names the developer ID as stored, the resource path and the service
/// account.
///
/// Never carries a private key, token or key id: the message is passed through
/// `redactingSecrets(_:)`, and nothing else is read from the credentials but
/// the service account e-mail the caller hands in.
struct GooglePlayErrorDetails: Equatable, Sendable {

    /// Where an error came from, when the error tells.
    enum Source: String, Equatable, Sendable {
        /// Google answered the request with this error.
        case googlePlay
        /// The app (or its core) refused the call before sending anything:
        /// the core says "nothing was sent to Google".
        case localValidation
        /// The request didn't get an answer (offline, timeout, DNS…).
        case connection
        /// The service account key file couldn't be used.
        case keyFile
    }

    /// The operation, named as the API calls it where known.
    let operation: String
    /// The error's type and case, e.g. `StackError.Http`.
    let kind: String
    let httpStatus: Int?
    /// The core's or Google's message, verbatim but for redacted secrets.
    let message: String?
    let source: Source?
    let call: GooglePlayUsersCall?

    init(error: Error, operation: GooglePlayErrorTranslator.Operation, call: GooglePlayUsersCall? = nil) {
        self.operation = call?.method.rawValue ?? operation.technicalName
        self.call = call
        let facts = Self.facts(of: error)
        self.kind = facts.kind
        self.httpStatus = facts.status
        self.message = facts.message.map(Self.redactingSecrets).flatMap(Self.nonBlank)
        self.source = facts.source
    }

    // MARK: - Report lines

    /// One line per fact, labelled, in the order a reader needs them. Labels
    /// are localized; values (API names, Google's message, IDs) stay verbatim.
    var lines: [String] {
        var lines = [
            String(localized: "Operation: \(operation)", comment: "Error report technical line. Argument: the Google Play API operation, e.g. developers.users.list."),
            String(localized: "Error kind: \(kind)", comment: "Error report technical line. Argument: the error's type and case, e.g. StackError.Http.")
        ]
        if let httpStatus {
            lines.append(String(localized: "HTTP status: \(httpStatus)", comment: "Error report technical line. Argument: the HTTP status code, e.g. 404."))
        }
        if let source {
            lines.append(String(localized: "Source: \(source.title)", comment: "Error report technical line. Argument: where the error came from (Google Play, a local check, the network, the key file)."))
        }
        if let message {
            lines.append(String(localized: "Message: \(message)", comment: "Error report technical line. Argument: the error message from Google or the app's core, verbatim and in English."))
        }
        if let call {
            lines += GooglePlayDeveloperId.diagnosticLines(for: call.developerId, label: .stored)
            lines.append(String(localized: "Resource: \(call.resourcePath)", comment: "Error report technical line. Argument: the Google Play API resource path called, e.g. developers/123/users."))
            if let serviceAccount = Self.nonBlank(call.serviceAccountEmail ?? "") {
                lines.append(String(localized: "Service account: \(serviceAccount)", comment: "Error report technical line. Argument: the service account e-mail (client_email) the app calls Google as."))
            }
        }
        return lines
    }

    /// Logs the failure as one unlocalized `os.Logger` error line: operation,
    /// kind, status, source, developer ID, resource and message. No secret is
    /// ever part of it (see the type's documentation).
    func log(tag: String) {
        let status = httpStatus.map(String.init) ?? "-"
        let source = source?.rawValue ?? "unknown"
        let developerId = call.map { "\"\($0.developerId)\"" } ?? "-"
        let resource = call?.resourcePath ?? "-"
        let message = message ?? "-"
        // The developer ID and the operation are public identifiers; the
        // resource may hold a user's e-mail and Google's message the service
        // account's, so both stay private (redacted outside a debugger).
        Log.print.error("[\(tag, privacy: .public)] \(operation, privacy: .public) failed — kind: \(kind, privacy: .public), status: \(status, privacy: .public), source: \(source, privacy: .public), developerId: \(developerId, privacy: .public), resource: \(resource), message: \(message)")
    }

    // MARK: - Redaction

    /// `text` with anything that looks like a credential replaced: PEM blocks,
    /// `private_key` / `private_key_id` JSON fields, bearer and OAuth tokens,
    /// JWTs and 40-hex key ids. Google's and the core's messages never carry
    /// them, but a report must not leak one if that ever changes.
    static func redactingSecrets(_ text: String) -> String {
        let rules: [(pattern: String, template: String)] = [
            (#"-----BEGIN [A-Z ]+-----[\s\S]*?(?:-----END [A-Z ]+-----|$)"#, "[redacted key]"),
            (#"("private_key(?:_id)?"\s*:\s*)"(?:[^"\\]|\\.)*""#, "$1\"[redacted]\""),
            (#"(?i)\b(bearer)\s+[A-Za-z0-9._~+/=-]+"#, "$1 [redacted]"),
            (#"(?i)\b(access_token|refresh_token|id_token|assertion|client_secret)(["']?\s*[:=]\s*["']?)[^"'&\s,}]+"#, "$1$2[redacted]"),
            (#"\bya29\.[A-Za-z0-9._-]+"#, "[redacted token]"),
            (#"\beyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+"#, "[redacted token]"),
            (#"\b[0-9a-fA-F]{40}\b"#, "[redacted]")
        ]
        var result = text
        for rule in rules {
            guard let regex = try? NSRegularExpression(pattern: rule.pattern) else { continue }
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: rule.template)
        }
        return result
    }

    // MARK: - Private

    private struct Facts {
        var kind: String
        var status: Int?
        var message: String?
        var source: Source?
    }

    private static func facts(of error: Error) -> Facts {
        if let parseError = error as? GooglePlayServiceAccount.ParseError {
            // Cases carry only field names and the declared `type`.
            return Facts(kind: "GooglePlayServiceAccount.ParseError", message: String(describing: parseError), source: .keyFile)
        }
        if error is OfflineError {
            return Facts(kind: "OfflineError.noConnection", source: .connection)
        }
        guard let stackError = error as? StackError else {
            let nsError = error as NSError
            return Facts(kind: "\(String(reflecting: type(of: error))) (\(nsError.domain) \(nsError.code))", message: error.localizedDescription)
        }
        switch stackError {
        case .Http(let status, let message):
            let local = GooglePlayErrorTranslator.isLocalRejection(message)
            return Facts(kind: "StackError.Http", status: Int(status), message: message, source: local ? .localValidation : .googlePlay)
        case .Auth(let message):
            return Facts(kind: "StackError.Auth", message: message, source: .googlePlay)
        case .Network(let message):
            return Facts(kind: "StackError.Network", message: message, source: .connection)
        case .InvalidCredentials(let message):
            return Facts(kind: "StackError.InvalidCredentials", message: message, source: .keyFile)
        case .Decode(let message):
            return Facts(kind: "StackError.Decode", message: message)
        case .Unsupported(let message):
            return Facts(kind: "StackError.Unsupported", message: message, source: .localValidation)
        case .ReleaseNotFound(let message):
            return Facts(kind: "StackError.ReleaseNotFound", message: message)
        case .PendingAgreements(let message):
            return Facts(kind: "StackError.PendingAgreements", message: message)
        case .SubmissionNotRemovable(let message):
            return Facts(kind: "StackError.SubmissionNotRemovable", message: message)
        }
    }

    private static func nonBlank(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

// MARK: - Source titles

private extension GooglePlayErrorDetails.Source {

    var title: String {
        switch self {
        case .googlePlay:
            return String(localized: "Google Play API (Google's answer)", comment: "Error report technical value: the error came from Google's response.")
        case .localValidation:
            return String(localized: "StackConnect, before any request (nothing was sent to Google)", comment: "Error report technical value: the app refused the call locally.")
        case .connection:
            return String(localized: "Network (the request may not have reached Google)", comment: "Error report technical value: the request got no answer.")
        case .keyFile:
            return String(localized: "Service account key file", comment: "Error report technical value: the JSON key couldn't be used.")
        }
    }
}

// MARK: - Operation names

extension GooglePlayErrorTranslator.Operation {

    /// The operation for a report when no users call names it.
    var technicalName: String {
        switch self {
        case .general:         return "general (apps, reviews, package check)"
        case .appContentRead:  return "edits (read)"
        case .replyToReview:   return "reviews.reply"
        case .releaseChange:   return "edits.commit (release change)"
        case .users:           return GooglePlayUsersCall.Method.list.rawValue
        case .inviteUser:      return GooglePlayUsersCall.Method.invite.rawValue
        case .userChange:      return "developers.users (change)"
        }
    }
}

// MARK: - Developer ID diagnostics

extension GooglePlayDeveloperId {

    /// Which value the diagnostic lines describe.
    enum DiagnosticLabel {
        /// The ID saved on the account (what the calls send).
        case stored
        /// What the user typed or pasted.
        case entered
    }

    /// Lines describing `value` for a report: the value quoted verbatim (so
    /// spaces and invisible characters show), its length, whether it is digits
    /// only and, when not, the characters that aren't digits.
    static func diagnosticLines(for value: String, label: DiagnosticLabel) -> [String] {
        let quoted = "\"\(value)\""
        var lines = [
            label == .stored
                ? String(localized: "Developer ID (as stored): \(quoted)", comment: "Error report technical line. Argument: the Google Play developer ID saved on the account, in quotes.")
                : String(localized: "Developer ID (as entered): \(quoted)", comment: "Error report technical line. Argument: the Google Play developer ID the user typed, in quotes."),
            String(localized: "Developer ID length: \(value.count)", comment: "Error report technical line. Argument: number of characters of the developer ID.")
        ]
        let isDigitsOnly = !value.isEmpty && value.unicodeScalars.allSatisfy { ("0"..."9").contains($0) }
        if isDigitsOnly {
            lines.append(String(localized: "Developer ID format: digits only", comment: "Error report technical line: the developer ID is a plain number."))
        } else {
            lines.append(String(localized: "Developer ID format: not digits only (Google needs the number from the Play Console URL)", comment: "Error report technical line: the developer ID has other characters than digits."))
            let unexpected = unexpectedCharacters(in: value)
            if !unexpected.isEmpty {
                lines.append(String(localized: "Developer ID unexpected characters: \(unexpected)", comment: "Error report technical line. Argument: the non-digit characters of the developer ID as Unicode code points, e.g. U+0020, U+200B."))
            }
        }
        return lines
    }

    /// The distinct non-digit characters of `value` as code points
    /// (`U+0020, U+0061`), at most 8.
    private static func unexpectedCharacters(in value: String) -> String {
        var seen: [Unicode.Scalar] = []
        for scalar in value.unicodeScalars where !("0"..."9").contains(scalar) && !seen.contains(scalar) {
            seen.append(scalar)
        }
        var described = seen.prefix(8).map { String(format: "U+%04X", $0.value) }
        if seen.count > 8 { described.append("…") }
        return described.joined(separator: ", ")
    }
}
