import Foundation
import StackProtocols
@testable import StackConnect

// MARK: - Store

/// In-memory `NetworkAuditStoring`.
actor MockNetworkAuditStore: NetworkAuditStoring {

    private(set) var events: [NetworkAuditEvent] = []
    private(set) var purgeCutoffs: [Date] = []
    private(set) var deleteAllCount = 0

    init(events: [NetworkAuditEvent] = []) {
        self.events = events
    }

    func append(_ event: NetworkAuditEvent) {
        events.append(event)
    }

    func summaries(since cutoff: Date) -> [NetworkAuditEventSummary] {
        events.filter { $0.date >= cutoff }.sorted { $0.date > $1.date }.map(\.summary)
    }

    func event(for summary: NetworkAuditEventSummary) -> NetworkAuditEvent? {
        events.first { $0.id == summary.id }
    }

    func count(before cutoff: Date) -> Int {
        events.filter { $0.date < cutoff }.count
    }

    func purge(before cutoff: Date) -> Int {
        purgeCutoffs.append(cutoff)
        let before = events.count
        events.removeAll { $0.date < cutoff }
        return before - events.count
    }

    func deleteAll() {
        deleteAllCount += 1
        events.removeAll()
    }

    func rewrite(_ transform: @escaping @Sendable (NetworkAuditEvent) -> NetworkAuditEvent?) -> Int {
        var count = 0
        events = events.map { event in
            guard let updated = transform(event) else { return event }
            count += 1
            return updated
        }
        return count
    }

    func stats() -> NetworkAuditStorageStats {
        NetworkAuditStorageStats(eventCount: events.count, byteCount: Int64(events.count * 100), oldestDate: events.map(\.date).min())
    }
}

// MARK: - Settings

final class MockNetworkAuditSettings: NetworkAuditSettingsProviding, @unchecked Sendable {
    var retention: NetworkAuditRetention = .default
    var recordsFullBodies = true
}

// MARK: - Device services

final class MockNetworkAuditAuthenticator: NetworkAuditOwnerAuthenticating, @unchecked Sendable {
    var result: Bool
    private(set) var reasons: [String] = []

    init(result: Bool = true) {
        self.result = result
    }

    func authenticate(reason: String) async -> Bool {
        reasons.append(reason)
        return result
    }
}

final class MockNetworkAuditPasteboard: NetworkAuditPasteboardWriting, @unchecked Sendable {
    private(set) var copies: [(text: String, sensitive: Bool)] = []

    func copy(_ text: String, sensitive: Bool) {
        copies.append((text, sensitive))
    }
}

final class MockNetworkAuditLocalRecorder: NetworkAuditLocalRecording, @unchecked Sendable {
    private(set) var imports: [(fileName: String, byteCount: Int64)] = []
    private(set) var exports: [NetworkAuditExportRecord] = []

    func recordFileImport(fileName: String, byteCount: Int64) {
        imports.append((fileName, byteCount))
    }

    func recordExport(_ export: NetworkAuditExportRecord) {
        exports.append(export)
    }
}

// MARK: - Fixtures

enum NetworkAuditFixtures {

    /// 2026-11-24 14:32:08 UTC.
    static let now = Date(timeIntervalSince1970: 1_795_530_728)

    static var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    /// An unsigned JWT with the given claims (enough for claim parsing).
    static func jwt(_ claims: [String: Any]) -> String {
        func encode(_ object: [String: Any]) -> String {
            let data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data()
            return data.base64EncodedString()
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
        }
        return "\(encode(["alg": "ES256", "kid": "2X9B4K7Q3Z", "typ": "JWT"])).\(encode(claims)).c2lnbmF0dXJlLXZhbHVl"
    }

    static func ascJWT(expiresAt: Date) -> String {
        jwt(["iss": "69a6de70-03db-47e3", "exp": Int(expiresAt.timeIntervalSince1970), "aud": "appstoreconnect-v1"])
    }

    static func exchange(
        url: String = "https://api.appstoreconnect.apple.com/v1/apps?limit=200&include=appStoreVersions",
        method: String = "GET",
        authorization: String? = nil,
        requestHeaders: [NetworkAuditExchange.HeaderField] = [],
        requestBody: Data? = nil,
        status: Int? = 200,
        responseHeaders: [NetworkAuditExchange.HeaderField] = [.init(name: "Content-Type", value: "application/json")],
        responseBody: Data? = Data(#"{"data":[{"id":"1","type":"apps"}]}"#.utf8),
        startedAt: Date = now,
        error: String? = nil
    ) -> NetworkAuditExchange {
        var headers = [NetworkAuditExchange.HeaderField(name: "Accept", value: "application/json")]
        if let authorization {
            headers.append(.init(name: "Authorization", value: authorization))
        }
        headers += requestHeaders
        return NetworkAuditExchange(
            source: .urlSession,
            startedAt: startedAt,
            duration: 0.412,
            method: method,
            url: URL(string: url)!,
            requestHeaders: headers,
            requestBody: requestBody,
            requestBodyLength: Int64(requestBody?.count ?? 0),
            statusCode: status,
            responseHeaders: responseHeaders,
            responseBody: responseBody,
            responseBodyLength: Int64(responseBody?.count ?? 0),
            wireBytesSent: 1_229,
            wireBytesReceived: 9_100,
            tlsVersion: "TLS 1.3",
            httpVersion: "HTTP/2",
            errorDescription: error
        )
    }

    /// A stored event, built by a real recorder (masking included).
    static func event(
        _ exchange: NetworkAuditExchange = exchange(),
        vault: NetworkAuditSecretSealing = NetworkAuditSecretVault(keychain: MockKeyStorable()),
        recordsFullBodies: Bool = true
    ) -> NetworkAuditEvent {
        let settings = MockNetworkAuditSettings()
        settings.recordsFullBodies = recordsFullBodies
        let recorder = NetworkAuditRecorder(store: MockNetworkAuditStore(), settings: settings, vault: vault, now: { now })
        return recorder.makeEvent(from: exchange)
    }

    @MainActor
    static func dependencies(
        store: NetworkAuditStoring = MockNetworkAuditStore(),
        settings: NetworkAuditSettingsProviding = MockNetworkAuditSettings(),
        vault: NetworkAuditSecretSealing = NetworkAuditSecretVault(keychain: MockKeyStorable()),
        recorder: NetworkAuditLocalRecording? = nil,
        authenticator: NetworkAuditOwnerAuthenticating = MockNetworkAuditAuthenticator(),
        pasteboard: NetworkAuditPasteboardWriting = MockNetworkAuditPasteboard(),
        now: Date = now
    ) -> NetworkAuditDependencies {
        NetworkAuditDependencies(
            store: store,
            settings: settings,
            vault: vault,
            localRecorder: recorder,
            authenticator: authenticator,
            pasteboard: pasteboard,
            exporter: NetworkAuditExporter(appVersion: "2.4.0", timeZone: TimeZone(identifier: "UTC")!),
            now: { now }
        )
    }
}
