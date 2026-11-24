import Foundation

// MARK: - Category

/// Who an audit event talks to. Drives the list filter chips and the tint of
/// the category badge.
enum NetworkAuditCategory: String, Codable, CaseIterable, Sendable, Hashable {
    case apple
    case google
    /// The app's own analytics, crash reports and remote configuration.
    case telemetry
    /// Nothing left the device (file imports, exports).
    case local
    /// A host the catalog doesn't know. Shown under "All" only.
    case other
}

// MARK: - Kind

enum NetworkAuditEventKind: String, Codable, Sendable, Hashable {
    /// An HTTP exchange.
    case http
    /// A file read into the app (a `.p8` / service-account key), no content.
    case fileImport
    /// An export of audit events (copy or share), itself audited.
    case export
}

enum NetworkAuditDirection: String, Codable, Sendable, Hashable {
    case outbound
    case inbound
}

// MARK: - Header / Body

/// A header as stored: secret values are masked at capture time. The original
/// of a secret header is only kept inside the event's encrypted `sealedSecrets`.
struct NetworkAuditHeader: Codable, Sendable, Hashable {
    let name: String
    /// The masked value for secrets (`Bearer [MASKED]`), the value otherwise.
    let value: String
    /// `true` when the value is a credential (`Authorization`, cookies, …).
    var isSecret: Bool = false
    /// UI hint for a masked secret, e.g. `Bearer eyJhbG••••••••`.
    var maskedPreview: String?
}

/// A request or response body as stored (already masked).
struct NetworkAuditBody: Codable, Sendable, Hashable {
    enum Content: Codable, Sendable, Hashable {
        /// Readable text (JSON pretty printed), with secrets masked.
        case text(String)
        /// Binary content: only described, never stored.
        case binary
        /// The "Full bodies" setting was OFF when the event was recorded.
        case notRecorded
        /// The producer couldn't read it: a transport failure, a streamed
        /// request body, a response that failed to decode (Rust core).
        case unavailable
        /// No body at all (e.g. a GET).
        case empty
    }

    let content: Content
    let byteCount: Int64
    let contentType: String?
    /// `true` when the text was cut to `NetworkAuditRecorder.maxBodyBytes`.
    var isTruncated: Bool = false

    static let empty = NetworkAuditBody(content: .empty, byteCount: 0, contentType: nil)

    var text: String? {
        if case let .text(text) = content { return text }
        return nil
    }
}

// MARK: - Credential

/// The credential found in a request's `Authorization` header, described
/// without its value. Decides whether a cURL export may carry it (see
/// `NetworkAuditCredentialPolicy`).
struct NetworkAuditCredentialInfo: Codable, Sendable, Hashable {
    enum Kind: String, Codable, Sendable, Hashable {
        /// App Store Connect API JWT (20 minutes at most). Short-lived.
        case appStoreConnectJWT
        /// Google OAuth access token (`ya29.…`, 1 hour). Short-lived.
        case googleAccessToken
        /// The Apple ID web session's cookies (Rust core). Long-lived: always masked.
        case appleSessionCookie
        /// A signed OAuth assertion (service account token exchange). Always masked.
        case oauthAssertion
        /// Anything else (other JWTs, API keys, basic auth): always masked.
        case other
    }

    let kind: Kind
    /// When the token stops working, if known.
    let expiresAt: Date?

    var isShortLived: Bool { kind == .appStoreConnectJWT || kind == .googleAccessToken }
}

// MARK: - Event

enum NetworkAuditEventSource: String, Codable, Sendable, Hashable {
    case urlSession
    case rustCore
}

/// One audit entry, as stored on disk. Everything except `sealedSecrets` is
/// already masked; `sealedSecrets` is AES-GCM sealed with a Keychain key
/// (`NetworkAuditSecretVault`) and only opened after Face ID.
struct NetworkAuditEvent: Codable, Sendable, Hashable, Identifiable {
    let id: UUID
    let kind: NetworkAuditEventKind
    let direction: NetworkAuditDirection
    var category: NetworkAuditCategory
    let date: Date
    var duration: TimeInterval?
    /// `GET`, `POST`… for HTTP; `IMPORT` / `EXPORT` for local events.
    let method: String
    /// Masked full URL (secret query parameters masked). `nil` for local events.
    let url: String?
    /// Host for HTTP; a short label for local events ("iOS Files").
    let host: String
    /// Path + masked query for HTTP; a short description for local events.
    let path: String
    var statusCode: Int?
    /// Human status for local events ("Read", "Copied", "Face ID").
    var statusText: String?
    var errorDescription: String?
    var bytesSent: Int64
    var bytesReceived: Int64
    var wireBytesSent: Int64?
    var wireBytesReceived: Int64?
    /// e.g. "TLS 1.3 · HTTP/2".
    var connection: String?
    var origin: String?
    var purpose: String?
    var accountName: String?
    var requestHeaders: [NetworkAuditHeader]
    var responseHeaders: [NetworkAuditHeader]
    var requestBody: NetworkAuditBody
    var responseBody: NetworkAuditBody
    var credential: NetworkAuditCredentialInfo?
    /// Encrypted originals of the secret headers (`[headerKey: value]`).
    var sealedSecrets: Data?
    /// Who recorded it. `nil` in events stored before the Rust core hook.
    var source: NetworkAuditEventSource? = nil
    /// The core operation that caused the call, raw (`reviews.fetch_customer_reviews`).
    var operation: String? = nil
    /// The operation that started `operation`, readable ("Ratings and Reviews · …").
    var parentOrigin: String? = nil
    /// `1` for a first attempt; `2`+ for a retry (Rust core).
    var attempt: Int? = nil

    /// HTTP 2xx/3xx, or a local event that didn't fail.
    var isSuccess: Bool {
        if errorDescription != nil { return false }
        guard let statusCode else { return kind != .http }
        return (200..<400).contains(statusCode)
    }

    var summary: NetworkAuditEventSummary {
        NetworkAuditEventSummary(
            id: id,
            kind: kind,
            direction: direction,
            category: category,
            date: date,
            method: method,
            host: host,
            path: path,
            statusCode: statusCode,
            statusText: statusText,
            isSuccess: isSuccess,
            bytesSent: bytesSent,
            bytesReceived: bytesReceived
        )
    }
}

/// The light, list-sized part of an event (the on-disk index line).
struct NetworkAuditEventSummary: Codable, Sendable, Hashable, Identifiable {
    let id: UUID
    let kind: NetworkAuditEventKind
    let direction: NetworkAuditDirection
    let category: NetworkAuditCategory
    let date: Date
    let method: String
    let host: String
    let path: String
    let statusCode: Int?
    let statusText: String?
    let isSuccess: Bool
    let bytesSent: Int64
    let bytesReceived: Int64
}

// MARK: - Storage stats

struct NetworkAuditStorageStats: Equatable, Sendable {
    var eventCount: Int
    var byteCount: Int64
    var oldestDate: Date?

    static let empty = NetworkAuditStorageStats(eventCount: 0, byteCount: 0, oldestDate: nil)
}

// MARK: - Re-categorizing

extension NetworkAuditEventSummary {
    /// Events stored as `.other` before the host catalog knew their host get
    /// the catalog's current category when shown.
    func withCurrentCategory() -> NetworkAuditEventSummary {
        guard kind == .http, category == .other else { return self }
        let current = NetworkAuditHostCatalog.entry(host: host, path: path).category
        guard current != .other else { return self }
        return NetworkAuditEventSummary(
            id: id, kind: kind, direction: direction, category: current, date: date, method: method,
            host: host, path: path, statusCode: statusCode, statusText: statusText, isSuccess: isSuccess,
            bytesSent: bytesSent, bytesReceived: bytesReceived
        )
    }
}

extension NetworkAuditEvent {
    /// See `NetworkAuditEventSummary.withCurrentCategory()`.
    func withCurrentCategory() -> NetworkAuditEvent {
        guard kind == .http, category == .other else { return self }
        let current = NetworkAuditHostCatalog.entry(host: host, path: path).category
        guard current != .other else { return self }
        var copy = self
        copy.category = current
        return copy
    }
}
