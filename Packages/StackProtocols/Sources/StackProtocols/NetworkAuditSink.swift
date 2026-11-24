import Foundation

// MARK: - Exchange

/// One HTTP exchange the app made, as raw as the network layer saw it, handed
/// to the on-device network audit (Settings › Privacy › Audit).
///
/// Every producer fills the same type: the app's `URLProtocol` recorder for
/// `URLSession` traffic, and the adapter of the Rust core's audit hook for the
/// App Store Connect / Google Play / Apple ID traffic executed inside
/// `StackCoreRust` (`source == .rustCore`).
///
/// Security: the value carries credentials as they went over the wire
/// (`Authorization`, cookies, tokens in bodies). A sink must mask or encrypt
/// them before anything is persisted, and must never log them.
public struct NetworkAuditExchange: Sendable, Equatable {

    /// Who produced the exchange.
    public enum Source: String, Sendable, Codable, Equatable {
        /// The app's own `URLSession`s and the third-party SDKs that use one.
        case urlSession
        /// The Rust core (`StackCoreRust`), through its `NetworkAuditSink` hook.
        case rustCore
    }

    /// One header line, in the order it was sent or received.
    public struct HeaderField: Sendable, Equatable, Codable {
        public let name: String
        public let value: String

        public init(name: String, value: String) {
            self.name = name
            self.value = value
        }
    }

    public var source: Source
    public var startedAt: Date
    /// Wall time from the request start to the last byte (or the failure).
    public var duration: TimeInterval?
    public var method: String
    public var url: URL
    public var requestHeaders: [HeaderField]
    /// The body that was sent, when available. `requestBodyLength` is set even
    /// when the body itself is not handed over.
    public var requestBody: Data?
    public var requestBodyLength: Int64
    /// `nil` when the request failed before a response arrived.
    public var statusCode: Int?
    public var responseHeaders: [HeaderField]
    /// The decoded (decompressed) response body, when available.
    public var responseBody: Data?
    public var responseBodyLength: Int64
    /// Bytes on the wire (headers + encoded body), when the producer knows them.
    public var wireBytesSent: Int64?
    public var wireBytesReceived: Int64?
    /// e.g. "TLS 1.3".
    public var tlsVersion: String?
    /// e.g. "HTTP/2".
    public var httpVersion: String?
    /// A transport error (offline, timeout, cancelled…), never a credential.
    public var errorDescription: String?
    /// Screen or flow that started the request ("Home · pull to refresh").
    public var origin: String?
    /// Why the request was made ("Sync the app list").
    public var purpose: String?
    /// Display name of the account whose credentials were used.
    public var accountName: String?

    public init(
        source: Source,
        startedAt: Date,
        duration: TimeInterval? = nil,
        method: String,
        url: URL,
        requestHeaders: [HeaderField] = [],
        requestBody: Data? = nil,
        requestBodyLength: Int64 = 0,
        statusCode: Int? = nil,
        responseHeaders: [HeaderField] = [],
        responseBody: Data? = nil,
        responseBodyLength: Int64 = 0,
        wireBytesSent: Int64? = nil,
        wireBytesReceived: Int64? = nil,
        tlsVersion: String? = nil,
        httpVersion: String? = nil,
        errorDescription: String? = nil,
        origin: String? = nil,
        purpose: String? = nil,
        accountName: String? = nil
    ) {
        self.source = source
        self.startedAt = startedAt
        self.duration = duration
        self.method = method
        self.url = url
        self.requestHeaders = requestHeaders
        self.requestBody = requestBody
        self.requestBodyLength = requestBodyLength
        self.statusCode = statusCode
        self.responseHeaders = responseHeaders
        self.responseBody = responseBody
        self.responseBodyLength = responseBodyLength
        self.wireBytesSent = wireBytesSent
        self.wireBytesReceived = wireBytesReceived
        self.tlsVersion = tlsVersion
        self.httpVersion = httpVersion
        self.errorDescription = errorDescription
        self.origin = origin
        self.purpose = purpose
        self.accountName = accountName
    }
}

// MARK: - Sink

/// Receives every HTTP exchange the app makes, for the on-device network audit.
///
/// Must be cheap and non-blocking: producers call it from networking threads.
/// The implementation owns masking, encryption and persistence.
///
/// Named apart from the Rust core's generated `StackCoreRust.NetworkAuditSink`
/// (its structured hook): the app's `NetworkAuditCoreSink` adapts that one's
/// entries into this exchange type before they reach the recorder.
public protocol NetworkAuditExchangeSink: Sendable {
    func record(_ exchange: NetworkAuditExchange)
}
