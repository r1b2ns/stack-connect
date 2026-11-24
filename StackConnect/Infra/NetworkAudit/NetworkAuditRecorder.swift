import CryptoKit
import Foundation
import StackProtocols

// MARK: - Local events

/// Records events that never touch the network: files read into the app and
/// exports of the audit log itself.
protocol NetworkAuditLocalRecording: Sendable {
    func recordFileImport(fileName: String, byteCount: Int64)
    func recordExport(_ export: NetworkAuditExportRecord)
}

/// What an export did, for its own audit entry.
struct NetworkAuditExportRecord: Equatable, Sendable {
    enum Action: String, Sendable {
        case copied
        case shared
    }

    let formatName: String
    /// e.g. "GET /v1/apps" for one event, "142 events · Today" for a batch.
    let subject: String
    let action: Action
    let includesRealToken: Bool
    let byteCount: Int64
}

// MARK: - Recorder

/// Turns raw exchanges into masked, encrypted audit events and stores them.
///
/// Implements `NetworkAuditExchangeSink` for the `URLProtocol` recorder; the
/// Rust core's entries come through `recordCore(_:annotations:)`
/// (`NetworkAuditCoreSink`), with the core's hints.
///
/// Masking happens here, before anything is written: secret headers are
/// replaced by `[MASKED]` and their originals sealed (`NetworkAuditSecretVault`);
/// secrets in URLs and bodies (refresh tokens, assertions, private keys…) are
/// masked for good and never stored.
final class NetworkAuditRecorder: NetworkAuditExchangeSink, NetworkAuditLocalRecording, @unchecked Sendable {

    /// The installed recorder, or `nil` while the audit is off (feature flag
    /// `networkAudit` OFF, unit-test host, fake data mode).
    nonisolated(unsafe) static var shared: NetworkAuditRecorder?

    /// Longest body text kept per event, after masking.
    static let maxBodyBytes = 256 * 1024
    /// Bodies bigger than this are not even masked (and not stored).
    static let maxMaskableBodyBytes = 8 * 1024 * 1024

    let store: NetworkAuditStoring
    let settings: NetworkAuditSettingsProviding
    let vault: NetworkAuditSecretSealing
    let tokenExpiries: NetworkAuditTokenExpiryRegistry
    /// Turns the Rust core's account ids into the names the user knows.
    let accounts: NetworkAuditAccountResolving?
    /// StackConnect's own identifiers, hidden before storage.
    let appIdentity: NetworkAuditAppIdentity
    private let now: @Sendable () -> Date

    init(
        store: NetworkAuditStoring,
        settings: NetworkAuditSettingsProviding,
        vault: NetworkAuditSecretSealing,
        tokenExpiries: NetworkAuditTokenExpiryRegistry = NetworkAuditTokenExpiryRegistry(),
        accounts: NetworkAuditAccountResolving? = nil,
        appIdentity: NetworkAuditAppIdentity = .current,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.appIdentity = appIdentity
        self.store = store
        self.settings = settings
        self.vault = vault
        self.tokenExpiries = tokenExpiries
        self.accounts = accounts
        self.now = now
    }

    // MARK: - Rust core entries

    /// Records an exchange of the Rust core (`NetworkAuditCoreSink`). Returns
    /// at once: masking, sealing and the write happen on a background task.
    func recordCore(_ exchange: NetworkAuditExchange, annotations: NetworkAuditAnnotations) {
        Task.detached(priority: .utility) { [self] in
            await persistCore(exchange, annotations: annotations)
        }
    }

    /// Awaitable for tests.
    func persistCore(_ exchange: NetworkAuditExchange, annotations: NetworkAuditAnnotations) async {
        var exchange = exchange
        if exchange.accountName == nil, let id = annotations.coreAccountId, let accounts {
            exchange.accountName = await accounts.accountName(forCoreAccountId: id)
        }
        await store.append(makeEvent(from: exchange, annotations: annotations))
    }

    // MARK: - NetworkAuditExchangeSink

    func record(_ exchange: NetworkAuditExchange) {
        Task.detached(priority: .utility) { [self] in
            await persist(exchange)
        }
    }

    /// Builds and stores the event of `exchange`. Awaitable for tests.
    func persist(_ exchange: NetworkAuditExchange) async {
        await store.append(makeEvent(from: exchange))
    }

    // MARK: - Local events

    func recordFileImport(fileName: String, byteCount: Int64) {
        let event = makeLocalEvent(
            kind: .fileImport,
            direction: .inbound,
            method: "IMPORT",
            host: String(localized: "iOS Files", comment: "Network audit: label of a file import event (the iOS Files app)."),
            path: String(localized: "\(Self.maskedFileName(fileName)) → key form", comment: "Network audit: a key file read into the Add Account form. Argument: the masked file name."),
            statusText: String(localized: "Read", comment: "Network audit: status of a file import event."),
            bytesSent: 0,
            bytesReceived: byteCount
        )
        Task.detached(priority: .utility) { [store] in await store.append(event) }
    }

    func recordExport(_ export: NetworkAuditExportRecord) {
        Task.detached(priority: .utility) { [self] in
            await persistExport(export)
        }
    }

    /// Awaitable for tests.
    func persistExport(_ export: NetworkAuditExportRecord) async {
        await store.append(makeExportEvent(export))
    }

    func makeExportEvent(_ export: NetworkAuditExportRecord) -> NetworkAuditEvent {
        let host = export.includesRealToken
            ? String(localized: "\(export.formatName) with token", comment: "Network audit: an export that carried a real token. Argument: the format (cURL).")
            : String(localized: "\(export.formatName) export", comment: "Network audit: an export of audit events. Argument: the format (JSON, HAR, CSV, cURL, Text).")
        let status: String
        if export.includesRealToken {
            status = String(localized: "Face ID", comment: "Network audit: status of an export confirmed with Face ID.")
        } else if export.action == .copied {
            status = String(localized: "Copied", comment: "Network audit: status of an export copied to the clipboard.")
        } else {
            status = String(localized: "Shared", comment: "Network audit: status of an export handed to the share sheet.")
        }
        return makeLocalEvent(
            kind: .export,
            direction: .outbound,
            method: "EXPORT",
            host: host,
            path: export.subject,
            statusText: status,
            bytesSent: export.byteCount,
            bytesReceived: 0
        )
    }

    // MARK: - Retention

    /// Deletes what is older than the retention period. Run at launch, when
    /// the app comes to the foreground and right after the period is reduced.
    @discardableResult
    func purgeExpired() async -> Int {
        await store.purge(before: settings.retention.cutoff(from: now()))
    }

    /// Deletes the whole log and the key of its sealed secrets.
    func deleteAll() async {
        await store.deleteAll()
        vault.destroyKey()
    }

    // MARK: - Event building

    func makeEvent(from exchange: NetworkAuditExchange, annotations: NetworkAuditAnnotations? = nil) -> NetworkAuditEvent {
        let url = exchange.url
        let host = url.host ?? url.absoluteString
        let catalog = NetworkAuditHostCatalog.entry(host: host, path: url.path)
        let extraSecretFields = annotations?.extraSecretFields ?? []

        var secrets: [String: String] = [:]
        var credential: NetworkAuditCredentialInfo?
        let requestHeaders = exchange.requestHeaders.enumerated().map { index, field -> NetworkAuditHeader in
            let header = NetworkAuditSecretMasker.maskHeader(name: field.name, value: field.value)
            if header.isSecret {
                secrets[Self.secretKey(request: true, index: index)] = field.value
            }
            if field.name.caseInsensitiveCompare("Authorization") == .orderedSame {
                credential = NetworkAuditSecretMasker.credentialInfo(forAuthorization: field.value) { [tokenExpiries] token in
                    tokenExpiries.expiry(of: token)
                }
            }
            return header
        }
        let responseHeaders = exchange.responseHeaders.enumerated().map { index, field -> NetworkAuditHeader in
            let header = NetworkAuditSecretMasker.maskHeader(name: field.name, value: field.value)
            if header.isSecret {
                secrets[Self.secretKey(request: false, index: index)] = field.value
            }
            return header
        }

        // A token endpoint response tells when the access token it issued
        // expires: remembered (hashed) so a later request using it can be
        // exported as cURL while it is valid.
        if let body = exchange.responseBody {
            tokenExpiries.registerTokenResponse(body, receivedAt: exchange.startedAt.addingTimeInterval(exchange.duration ?? 0))
        }

        let recordsBodies = settings.recordsFullBodies
        // URLSession bodies may still be compressed (the Firebase SDKs gzip
        // their requests); the Rust core hands them over decoded.
        let decodesBodies = exchange.source == .urlSession
        let requestBody = makeBody(
            exchange.requestBody,
            length: exchange.requestBodyLength,
            contentType: Self.headerValue("Content-Type", in: exchange.requestHeaders),
            recordsBodies: recordsBodies,
            state: annotations?.requestBodyState,
            extraSecretFields: extraSecretFields,
            contentEncoding: decodesBodies ? Self.headerValue("Content-Encoding", in: exchange.requestHeaders) : nil
        )
        let responseBody = makeBody(
            exchange.responseBody,
            length: exchange.responseBodyLength,
            contentType: Self.headerValue("Content-Type", in: exchange.responseHeaders),
            recordsBodies: recordsBodies,
            state: annotations?.responseBodyState,
            extraSecretFields: extraSecretFields,
            contentEncoding: decodesBodies ? Self.headerValue("Content-Encoding", in: exchange.responseHeaders) : nil,
            isResponse: true
        )
        if let annotations {
            credential = Self.resolveCredential(hint: annotations.credential, decoded: credential)
        }

        let connection = [exchange.tlsVersion, exchange.httpVersion].compactMap { $0 }.joined(separator: " · ")
        let category = annotations?.category ?? catalog.category
        // StackConnect's own telemetry: its keys and tokens belong to the
        // app's Firebase project. Masked for good, never sealed.
        let isAppTelemetry = category == .telemetry
        // A revealable original never carries StackConnect's own identifiers.
        let isUserTraffic = NetworkAuditAppIdentity.isUserAccountTraffic(category)
        secrets = secrets.mapValues { appIdentity.mask($0, isUserAccountTraffic: isUserTraffic).text }

        let event = NetworkAuditEvent(
            id: UUID(),
            kind: .http,
            direction: .outbound,
            category: category,
            date: exchange.startedAt,
            duration: exchange.duration,
            method: exchange.method.uppercased(),
            url: NetworkAuditSecretMasker.maskURL(url),
            host: host,
            path: NetworkAuditSecretMasker.maskedPathAndQuery(url),
            statusCode: exchange.statusCode,
            statusText: nil,
            errorDescription: exchange.errorDescription,
            bytesSent: exchange.requestBodyLength,
            bytesReceived: exchange.responseBodyLength,
            wireBytesSent: exchange.wireBytesSent,
            wireBytesReceived: exchange.wireBytesReceived,
            connection: connection.isEmpty ? nil : connection,
            origin: exchange.origin,
            purpose: exchange.purpose ?? catalog.purpose,
            accountName: exchange.accountName,
            requestHeaders: requestHeaders,
            responseHeaders: responseHeaders,
            requestBody: requestBody,
            responseBody: responseBody,
            credential: credential,
            sealedSecrets: isAppTelemetry ? nil : vault.seal(secrets),
            source: exchange.source == .rustCore ? .rustCore : .urlSession,
            operation: annotations?.operation,
            parentOrigin: annotations?.parentOrigin,
            attempt: annotations?.attempt
        )
        let telemetrySafe = isAppTelemetry ? (event.appTelemetrySanitized() ?? event) : event
        return telemetrySafe.appIdentitySanitized(appIdentity) ?? telemetrySafe
    }

    /// Drops what older versions kept of app telemetry secrets (sealed
    /// originals, token prefixes in previews) from the events on disk.
    /// Returns how many events were rewritten.
    @discardableResult
    func scrubAppTelemetrySecrets() async -> Int {
        await store.rewrite { [appIdentity] in $0.storageSanitized(identity: appIdentity) }
    }

    /// The core's credential hint wins over the app's own decoding of the
    /// `Authorization` header; the decoded expiry fills a hint without one
    /// (an opaque Google token whose token response was seen).
    static func resolveCredential(
        hint: NetworkAuditAnnotations.Credential,
        decoded: NetworkAuditCredentialInfo?
    ) -> NetworkAuditCredentialInfo? {
        switch hint {
        case .none:
            return decoded
        case .unauthenticated:
            return nil
        case let .known(kind, expiresAt):
            let fallback = decoded?.kind == kind ? decoded?.expiresAt : nil
            return NetworkAuditCredentialInfo(kind: kind, expiresAt: kind.isShortLivedKind ? (expiresAt ?? fallback) : nil)
        }
    }

    /// Key of a secret header inside the sealed box.
    static func secretKey(request: Bool, index: Int) -> String {
        "\(request ? "request" : "response").\(index)"
    }

    private func makeBody(
        _ data: Data?,
        length: Int64,
        contentType: String?,
        recordsBodies: Bool,
        state: NetworkAuditAnnotations.BodyState? = nil,
        extraSecretFields: Set<String> = [],
        contentEncoding: String? = nil,
        isResponse: Bool = false
    ) -> NetworkAuditBody {
        let byteCount = max(length, Int64(data?.count ?? 0))
        switch state {
        case .empty:
            return NetworkAuditBody(content: .empty, byteCount: 0, contentType: contentType)
        case .binary:
            return NetworkAuditBody(content: .binary, byteCount: byteCount, contentType: contentType)
        case .notCaptured:
            return NetworkAuditBody(content: .notRecorded, byteCount: byteCount, contentType: contentType)
        case .unavailable:
            return NetworkAuditBody(content: .unavailable, byteCount: byteCount, contentType: contentType)
        case .captured, .truncated, .none:
            break
        }
        guard byteCount > 0 else { return NetworkAuditBody(content: .empty, byteCount: 0, contentType: contentType) }
        guard recordsBodies, let data, data.count <= Self.maxMaskableBodyBytes else {
            return NetworkAuditBody(content: .notRecorded, byteCount: byteCount, contentType: contentType)
        }

        // Undo `Content-Encoding` first, so the real payload is what gets
        // classified, masked and stored.
        var payload = data
        var encodingName: String?
        var decodedCount: Int64?
        var cutWhileDecoding = false
        if let encoding = NetworkAuditBodyDecoder.Encoding(header: contentEncoding) {
            switch NetworkAuditBodyDecoder.decode(data, encoding: encoding, maxOutputBytes: Self.maxMaskableBodyBytes, allowsRawDeflate: !isResponse) {
            case let .decoded(decoded, isTruncated):
                payload = decoded
                encodingName = encoding.name
                decodedCount = Int64(decoded.count)
                cutWhileDecoding = isTruncated
            case .unsupported(let name):
                var body = NetworkAuditBody(content: .binary, byteCount: byteCount, contentType: contentType)
                body.encoding = name
                return body
            case .failed:
                var body = NetworkAuditBody(content: .binary, byteCount: byteCount, contentType: contentType)
                body.encoding = encoding.name
                return body
            case .passthrough:
                break
            }
        }

        func finish(_ text: String, format: NetworkAuditBody.Format) -> NetworkAuditBody {
            let utf8 = Array(text.utf8)
            let isCut = utf8.count > Self.maxBodyBytes
            var body = NetworkAuditBody(
                content: .text(isCut ? String(decoding: utf8.prefix(Self.maxBodyBytes), as: UTF8.self) : text),
                byteCount: byteCount,
                contentType: contentType,
                isTruncated: isCut || cutWhileDecoding || state == .truncated
            )
            body.encoding = encodingName
            body.decodedByteCount = decodedCount
            body.format = format
            return body
        }

        if let masked = NetworkAuditSecretMasker.maskBody(payload, contentType: contentType, extraSecretFields: extraSecretFields) {
            let isJSON = masked.hasPrefix("{") || masked.hasPrefix("[")
            return finish(masked, format: isJSON ? .json : .text)
        }
        // Binary: a decoded protobuf (Firebase Analytics) becomes a readable
        // tree, masked like any text (never raw bytes).
        if encodingName != nil || (contentType?.lowercased().contains("protobuf") ?? false),
           let fields = NetworkAuditProtobufDecoder.decode(payload) {
            let tree = NetworkAuditProtobufDecoder.render(fields)
            return finish(NetworkAuditSecretMasker.maskFreeText(tree), format: .protobuf)
        }
        var body = NetworkAuditBody(content: .binary, byteCount: byteCount, contentType: contentType)
        body.encoding = encodingName
        body.decodedByteCount = decodedCount
        return body
    }

    private func makeLocalEvent(
        kind: NetworkAuditEventKind,
        direction: NetworkAuditDirection,
        method: String,
        host: String,
        path: String,
        statusText: String,
        bytesSent: Int64,
        bytesReceived: Int64
    ) -> NetworkAuditEvent {
        NetworkAuditEvent(
            id: UUID(),
            kind: kind,
            direction: direction,
            category: .local,
            date: now(),
            duration: nil,
            method: method,
            url: nil,
            host: host,
            path: path,
            statusCode: nil,
            statusText: statusText,
            errorDescription: nil,
            bytesSent: bytesSent,
            bytesReceived: bytesReceived,
            wireBytesSent: nil,
            wireBytesReceived: nil,
            connection: nil,
            origin: nil,
            purpose: String(localized: "Nothing left this device.", comment: "Network audit: purpose of a local (import / export) event."),
            accountName: nil,
            requestHeaders: [],
            responseHeaders: [],
            requestBody: .empty,
            responseBody: .empty,
            credential: nil,
            sealedSecrets: nil
        )
    }

    private static func headerValue(_ name: String, in fields: [NetworkAuditExchange.HeaderField]) -> String? {
        fields.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.value
    }

    /// `AuthKey_2X9B4K7Q3Z.p8` → `AuthKey_••••.p8`; other names keep only
    /// their extension: a file name can carry a key ID or a project ID.
    static func maskedFileName(_ name: String) -> String {
        let ext = (name as NSString).pathExtension
        let suffix = ext.isEmpty ? "" : ".\(ext)"
        if name.hasPrefix("AuthKey_") {
            return "AuthKey_••••\(suffix)"
        }
        return "••••\(suffix)"
    }
}

// MARK: - Token expiry registry

/// Remembers when the Google access tokens seen in token responses expire,
/// keyed by a SHA-256 of the token (the token itself is never kept).
final class NetworkAuditTokenExpiryRegistry: @unchecked Sendable {

    private let lock = NSLock()
    private var expiries: [String: Date] = [:]

    func register(token: String, expiresAt: Date) {
        lock.lock()
        defer { lock.unlock() }
        expiries = expiries.filter { $0.value > Date() }
        expiries[Self.hash(token)] = expiresAt
    }

    func expiry(of token: String) -> Date? {
        lock.lock()
        defer { lock.unlock() }
        return expiries[Self.hash(token)]
    }

    /// Reads `{"access_token": …, "expires_in": …}` from a token response.
    func registerTokenResponse(_ body: Data, receivedAt: Date) {
        guard body.count < 64 * 1024,
              let json = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any],
              let token = json["access_token"] as? String,
              let expiresIn = (json["expires_in"] as? NSNumber)?.doubleValue else { return }
        register(token: token, expiresAt: receivedAt.addingTimeInterval(expiresIn))
    }

    private static func hash(_ token: String) -> String {
        SHA256.hash(data: Data(token.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
