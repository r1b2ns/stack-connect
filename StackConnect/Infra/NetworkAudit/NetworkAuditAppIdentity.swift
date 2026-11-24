import Foundation

/// The values that identify or protect StackConnect itself — not the user —
/// and are hidden from the audit (replaced with `[APP]` before storage, never
/// sealed, never revealable, copied or exported):
///
/// - the app's bundle identifier (and its extensions', which start with it);
/// - its own Firebase project, read from the bundled `GoogleService-Info.plist`:
///   `PROJECT_ID`, `GCM_SENDER_ID` (project number), `GOOGLE_APP_ID`,
///   `API_KEY`, `CLIENT_ID`, `REVERSED_CLIENT_ID`;
/// - its Sign in with Google OAuth client (`GoogleOAuthClientID` in Info.plist,
///   and the reversed form used as redirect scheme).
///
/// Scope, so the user's own data stays visible:
/// - App traffic (telemetry, unknown hosts, local events): every value above.
/// - The user's account traffic (App Store Connect, Apple ID, Google Play,
///   Google / Firebase APIs called with the user's credentials): only the
///   OAuth client identifiers. A bundle ID or Firebase project the user's own
///   account returns stays visible, even when it is StackConnect's own (the
///   developer auditing their own account).
struct NetworkAuditAppIdentity: Sendable, Equatable {

    static let mask = "[APP]"
    /// Shorter values could match unrelated text.
    static let minimumLength = 6

    /// Hidden in app traffic only.
    let appTrafficValues: [String]
    /// Hidden everywhere, the user's account traffic included.
    let everywhereValues: [String]

    static let empty = NetworkAuditAppIdentity(bundleIds: [], firebaseValues: [], oauthClientIds: [])

    /// The running app's identity.
    static let current: NetworkAuditAppIdentity = load(bundle: .main)

    init(bundleIds: [String], firebaseValues: [String], oauthClientIds: [String]) {
        let oauth = oauthClientIds.flatMap { id -> [String] in
            var forms = [id]
            let suffix = ".apps.googleusercontent.com"
            if id.hasSuffix(suffix) {
                forms.append("com.googleusercontent.apps." + id.dropLast(suffix.count))
            }
            return forms
        }
        everywhereValues = Self.expand(oauth)
        appTrafficValues = Self.expand(bundleIds + firebaseValues + oauth)
    }

    static func load(bundle: Bundle) -> NetworkAuditAppIdentity {
        var firebase: [String] = []
        var oauth: [String] = []
        if let url = bundle.url(forResource: "GoogleService-Info", withExtension: "plist"),
           let plist = NSDictionary(contentsOf: url) as? [String: Any] {
            for key in ["PROJECT_ID", "GCM_SENDER_ID", "GOOGLE_APP_ID", "API_KEY"] {
                if let value = plist[key] as? String { firebase.append(value) }
            }
            for key in ["CLIENT_ID", "REVERSED_CLIENT_ID"] {
                if let value = plist[key] as? String { oauth.append(value) }
            }
        }
        if let clientId = bundle.object(forInfoDictionaryKey: "GoogleOAuthClientID") as? String,
           !clientId.hasPrefix("$(") {
            oauth.append(clientId)
        }
        return NetworkAuditAppIdentity(
            bundleIds: [bundle.bundleIdentifier].compactMap { $0 },
            firebaseValues: firebase,
            oauthClientIds: oauth
        )
    }

    /// Each value plus its percent-encoded form (query strings), longest
    /// first so a value inside another is replaced as part of the longer one.
    private static func expand(_ values: [String]) -> [String] {
        var all = Set<String>()
        for value in values where value.count >= minimumLength {
            all.insert(value)
            if let encoded = value.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "-._~"))),
               encoded != value {
                all.insert(encoded)
            }
        }
        return all.sorted { $0.count == $1.count ? $0 < $1 : $0.count > $1.count }
    }

    var isEmpty: Bool { appTrafficValues.isEmpty }

    /// `text` with the app's values replaced by `[APP]`, and whether any was.
    func mask(_ text: String, isUserAccountTraffic: Bool) -> (text: String, didMask: Bool) {
        let values = isUserAccountTraffic ? everywhereValues : appTrafficValues
        var result = text
        for value in values where result.contains(value) {
            result = result.replacingOccurrences(of: value, with: Self.mask)
        }
        return (result, result != text)
    }

    /// The user's account traffic: their own App Store Connect, Apple ID,
    /// Google Play and Google / Firebase APIs.
    static func isUserAccountTraffic(_ category: NetworkAuditCategory) -> Bool {
        category == .apple || category == .google
    }
}

// MARK: - Event / summary

extension NetworkAuditEvent {

    /// The event with the app's own values hidden. `nil` when nothing changes.
    func appIdentitySanitized(_ identity: NetworkAuditAppIdentity) -> NetworkAuditEvent? {
        guard !identity.isEmpty else { return nil }
        let isUser = NetworkAuditAppIdentity.isUserAccountTraffic(category)
        var copy = self
        var changed = false
        func mask(_ text: String) -> String {
            let (masked, didMask) = identity.mask(text, isUserAccountTraffic: isUser)
            changed = changed || didMask
            return masked
        }
        copy.host = mask(host)
        copy.path = mask(path)
        copy.url = url.map(mask)
        copy.requestHeaders = requestHeaders.map { $0.appIdentitySanitized(identity, isUser: isUser, changed: &changed) }
        copy.responseHeaders = responseHeaders.map { $0.appIdentitySanitized(identity, isUser: isUser, changed: &changed) }
        copy.requestBody = requestBody.appIdentitySanitized(mask)
        copy.responseBody = responseBody.appIdentitySanitized(mask)
        guard changed else { return nil }
        copy.hidesAppData = true
        return copy
    }

    /// What every screen and export shows: current category, app telemetry
    /// secrets dropped, the app's own values hidden.
    func sanitizedForDisplay(identity: NetworkAuditAppIdentity = .current) -> NetworkAuditEvent {
        var event = withCurrentCategory()
        if let telemetry = event.appTelemetrySanitized() { event = telemetry }
        if let identified = event.appIdentitySanitized(identity) { event = identified }
        return event
    }

    /// `sanitizedForDisplay` when it differs from what is stored.
    func storageSanitized(identity: NetworkAuditAppIdentity = .current) -> NetworkAuditEvent? {
        let sanitized = sanitizedForDisplay(identity: identity)
        return sanitized == self ? nil : sanitized
    }

    /// Anything owned by StackConnect was hidden: its telemetry secrets or
    /// its identifiers.
    var hidesAppValues: Bool {
        hidesAppData == true || (isAppTelemetry && (requestHeaders + responseHeaders).contains(where: \.isSecret))
    }
}

extension NetworkAuditHeader {
    fileprivate func appIdentitySanitized(_ identity: NetworkAuditAppIdentity, isUser: Bool, changed: inout Bool) -> NetworkAuditHeader {
        let (value, didMaskValue) = identity.mask(value, isUserAccountTraffic: isUser)
        let (preview, didMaskPreview) = maskedPreview.map { identity.mask($0, isUserAccountTraffic: isUser) } ?? (nil, false)
        guard didMaskValue || didMaskPreview else { return self }
        changed = true
        var copy = NetworkAuditHeader(name: name, value: value, isSecret: isSecret, maskedPreview: preview)
        copy.isAppData = true
        return copy
    }
}

extension NetworkAuditBody {
    fileprivate func appIdentitySanitized(_ mask: (String) -> String) -> NetworkAuditBody {
        guard case let .text(text) = content else { return self }
        var copy = self
        copy.content = .text(mask(text))
        return copy
    }
}

extension NetworkAuditEventSummary {
    /// Host and path with the app's own values hidden (list rows of events
    /// stored before the masking).
    func sanitizedForDisplay(identity: NetworkAuditAppIdentity = .current) -> NetworkAuditEventSummary {
        let summary = withCurrentCategory()
        guard !identity.isEmpty else { return summary }
        let isUser = NetworkAuditAppIdentity.isUserAccountTraffic(summary.category)
        let (host, hostMasked) = identity.mask(summary.host, isUserAccountTraffic: isUser)
        let (path, pathMasked) = identity.mask(summary.path, isUserAccountTraffic: isUser)
        guard hostMasked || pathMasked else { return summary }
        return NetworkAuditEventSummary(
            id: summary.id, kind: summary.kind, direction: summary.direction, category: summary.category,
            date: summary.date, method: summary.method, host: host, path: path,
            statusCode: summary.statusCode, statusText: summary.statusText, isSuccess: summary.isSuccess,
            bytesSent: summary.bytesSent, bytesReceived: summary.bytesReceived
        )
    }
}
