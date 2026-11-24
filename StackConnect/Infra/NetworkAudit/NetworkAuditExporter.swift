import Foundation

// MARK: - Formats

/// Formats of a batch export (Export Records sheet).
enum NetworkAuditBatchFormat: String, CaseIterable, Identifiable, Sendable {
    case json
    case har
    case csv

    var id: String { rawValue }

    var title: String {
        switch self {
        case .json: return "JSON"
        case .har: return "HAR"
        case .csv: return "CSV"
        }
    }

    var fileExtension: String { rawValue }

    /// CSV has one line per event: bodies and headers stay out.
    var supportsBodies: Bool { self != .csv }
}

/// Formats of a single-event export (Export Event sheet).
enum NetworkAuditEventFormat: String, CaseIterable, Identifiable, Sendable {
    case curl
    case json
    case har
    case text

    var id: String { rawValue }

    var title: String {
        switch self {
        case .curl: return "cURL"
        case .json: return "JSON"
        case .har: return "HAR"
        case .text: return String(localized: "Text", comment: "Network audit: the plain text export format.")
        }
    }

    var fileExtension: String {
        switch self {
        case .curl: return "sh"
        case .json: return "json"
        case .har: return "har"
        case .text: return "txt"
        }
    }
}

// MARK: - Exporter

/// Renders audit events in every export format.
///
/// Stored events are already masked (`NetworkAuditSecretMasker`), and every
/// text that leaves here goes through `maskFreeText` once more. The only way
/// a real secret gets out is `curl(_:includeBody:realAuthorization:)`, whose
/// caller passes the decrypted `Authorization` only when
/// `NetworkAuditTokenInclusion` allows it (short-lived token, still valid,
/// Face ID confirmed).
struct NetworkAuditExporter {

    var appVersion: String = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    var timeZone: TimeZone = .current

    // MARK: - Batch

    func batch(_ events: [NetworkAuditEvent], format: NetworkAuditBatchFormat, includeBodies: Bool) -> String {
        switch format {
        case .json: return json(events, includeBodies: includeBodies)
        case .har: return har(events, includeBodies: includeBodies)
        case .csv: return csv(events)
        }
    }

    // MARK: - Single event

    func single(_ event: NetworkAuditEvent, format: NetworkAuditEventFormat, includeBody: Bool, realAuthorization: String? = nil) -> String {
        switch format {
        case .curl: return curl(event, includeBody: includeBody, realAuthorization: realAuthorization)
        case .json: return json(event, includeBody: includeBody)
        case .har: return har([event], includeBodies: includeBody)
        case .text: return text(event, includeBody: includeBody)
        }
    }

    // MARK: - JSON

    func json(_ events: [NetworkAuditEvent], includeBodies: Bool) -> String {
        encode(events.map { JSONEvent(event: $0, includeBody: includeBodies, timestamp: timestamp($0.date)) })
    }

    func json(_ event: NetworkAuditEvent, includeBody: Bool) -> String {
        encode(JSONEvent(event: event, includeBody: includeBody, timestamp: timestamp(event.date)))
    }

    // MARK: - HAR 1.2

    /// HTTP Archive 1.2. Local events (imports, exports) have no HTTP
    /// exchange and are left out.
    func har(_ events: [NetworkAuditEvent], includeBodies: Bool) -> String {
        let entries = events.filter { $0.kind == .http }.map { event -> HAR.Entry in
            let url = event.url ?? "https://\(event.host)\(event.path)"
            let httpVersion = event.connection?.components(separatedBy: " · ").last { $0.hasPrefix("HTTP") } ?? "HTTP/1.1"
            let durationMs = (event.duration ?? 0) * 1000
            let requestBody = includeBodies ? event.requestBody.text : nil
            let responseText = includeBodies ? event.responseBody.text : nil
            return HAR.Entry(
                startedDateTime: timestamp(event.date),
                time: durationMs,
                request: HAR.Request(
                    method: event.method,
                    url: url,
                    httpVersion: httpVersion,
                    headers: event.requestHeaders.map { HAR.NameValue(name: $0.name, value: $0.value) },
                    queryString: Self.queryItems(of: url),
                    cookies: [],
                    headersSize: -1,
                    bodySize: event.bytesSent,
                    postData: requestBody.map {
                        HAR.PostData(mimeType: event.requestBody.contentType ?? "application/octet-stream", text: $0)
                    }
                ),
                response: HAR.Response(
                    status: event.statusCode ?? 0,
                    statusText: event.statusCode.map(NetworkAuditStatus.reasonPhrase) ?? (event.errorDescription ?? ""),
                    httpVersion: httpVersion,
                    headers: event.responseHeaders.map { HAR.NameValue(name: $0.name, value: $0.value) },
                    cookies: [],
                    content: HAR.Content(
                        size: event.bytesReceived,
                        mimeType: event.responseBody.contentType ?? "",
                        text: responseText
                    ),
                    redirectURL: "",
                    headersSize: -1,
                    bodySize: event.wireBytesReceived ?? event.bytesReceived
                ),
                cache: HAR.Empty(),
                timings: HAR.Timings(send: 0, wait: durationMs, receive: 0),
                comment: [event.origin, event.purpose].compactMap { $0 }.joined(separator: " · ")
            )
        }
        let log = HAR.Log(
            log: HAR.LogBody(
                version: "1.2",
                creator: HAR.Creator(name: "StackConnect", version: appVersion),
                entries: entries
            )
        )
        return encode(log)
    }

    // MARK: - CSV

    static let csvHeader = "time,direction,method,host,path,status,sent,received,category"

    func csv(_ events: [NetworkAuditEvent]) -> String {
        var lines = [Self.csvHeader]
        for event in events {
            let status = event.statusCode.map(String.init) ?? event.statusText ?? event.errorDescription ?? ""
            let fields = [
                timestamp(event.date),
                event.direction.rawValue,
                event.method,
                event.host,
                event.path,
                status,
                String(event.bytesSent),
                String(event.bytesReceived),
                event.category.rawValue
            ]
            lines.append(fields.map(Self.csvField).joined(separator: ","))
        }
        return NetworkAuditSecretMasker.maskFreeText(lines.joined(separator: "\n") + "\n")
    }

    static func csvField(_ value: String) -> String {
        guard value.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    // MARK: - cURL

    /// A command to repeat the request in Terminal. `realAuthorization`
    /// replaces the masked `Authorization` header; every other secret stays
    /// masked (cookies, API keys, body fields).
    func curl(_ event: NetworkAuditEvent, includeBody: Bool, realAuthorization: String? = nil) -> String {
        let url = event.url ?? "https://\(event.host)\(event.path)"
        var head = "curl"
        if event.method != "GET" {
            head += " -X \(event.method)"
        }
        head += " " + Self.shellQuoted(NetworkAuditSecretMasker.maskFreeText(url))
        var parts = [head]
        // A decoded body goes out as text: its `Content-Encoding` would lie.
        let sendsDecodedBody = includeBody && event.requestBody.isDecoded && !(event.requestBody.text ?? "").isEmpty

        for header in event.requestHeaders where !Self.skippedCurlHeaders.contains(header.name.lowercased()) {
            if sendsDecodedBody, header.name.caseInsensitiveCompare("Content-Encoding") == .orderedSame { continue }
            let value: String
            if header.name.caseInsensitiveCompare("Authorization") == .orderedSame, let realAuthorization {
                value = realAuthorization
            } else {
                value = NetworkAuditSecretMasker.maskFreeText(header.value)
            }
            parts.append("-H \(Self.shellQuoted("\(header.name): \(value)"))")
        }
        if includeBody, let body = event.requestBody.text, !body.isEmpty {
            parts.append("--data-raw \(Self.shellQuoted(NetworkAuditSecretMasker.maskFreeText(body)))")
        }
        let command = parts.joined(separator: " \\\n  ")
        guard sendsDecodedBody, let encoding = event.requestBody.encoding else { return command }
        return "# The body was sent \(encoding)-compressed; it is shown decompressed and Content-Encoding is left out.\n" + command
    }

    /// curl computes these itself.
    private static let skippedCurlHeaders: Set<String> = ["content-length", "host", "connection"]

    static func shellQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    // MARK: - Text

    func text(_ event: NetworkAuditEvent, includeBody: Bool) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = timeZone
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium

        var lines: [String] = []
        lines.append("\(event.method) \(event.url ?? "\(event.host) \(event.path)")")
        var status = NetworkAuditStatus.title(for: event)
        if let duration = event.duration {
            status += " · \(Int((duration * 1000).rounded())) ms"
        }
        lines.append(String(localized: "Status: \(status)", comment: "Network audit text export: the status line. Argument: e.g. \"200 OK · 412 ms\"."))
        lines.append(String(localized: "When: \(formatter.string(from: event.date))", comment: "Network audit text export: the date line."))
        if let origin = event.origin {
            lines.append(String(localized: "Origin: \(origin)", comment: "Network audit text export: the screen or flow that made the request."))
        }
        if let purpose = event.purpose {
            lines.append(String(localized: "Purpose: \(purpose)", comment: "Network audit text export: why the request was made."))
        }
        let sent = NetworkAuditFormatting.bytes(event.bytesSent)
        let received = NetworkAuditFormatting.bytes(event.bytesReceived)
        lines.append(String(localized: "Sent: \(sent) · Received: \(received)", comment: "Network audit text export: byte counts."))
        for header in event.requestHeaders {
            lines.append("\(header.name): \(header.value)")
        }
        if includeBody {
            if let body = event.requestBody.text, !body.isEmpty {
                lines.append("")
                lines.append(String(localized: "Request:", comment: "Network audit text export: heading of the request body."))
                lines.append(body)
            }
            if let body = event.responseBody.text, !body.isEmpty {
                lines.append("")
                lines.append(String(localized: "Response:", comment: "Network audit text export: heading of the response body."))
                lines.append(body)
            }
        }
        return NetworkAuditSecretMasker.maskFreeText(lines.joined(separator: "\n"))
    }

    // MARK: - Helpers

    func timestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = timeZone
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private static func queryItems(of url: String) -> [HAR.NameValue] {
        guard let query = url.split(separator: "?", maxSplits: 1).dropFirst().first else { return [] }
        return query.split(separator: "&").map { item in
            let pair = item.split(separator: "=", maxSplits: 1).map(String.init)
            let name = pair.first?.removingPercentEncoding ?? pair.first ?? ""
            let value = pair.count > 1 ? (pair[1].removingPercentEncoding ?? pair[1]) : ""
            return HAR.NameValue(name: name, value: value)
        }
    }

    private func encode<T: Encodable>(_ value: T) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(value), let text = String(data: data, encoding: .utf8) else { return "" }
        return NetworkAuditSecretMasker.maskFreeText(text)
    }
}

// MARK: - JSON shape

private struct JSONEvent: Encodable {
    let id: String
    let time: String
    let kind: String
    let direction: String
    let category: String
    let method: String
    let url: String?
    let host: String
    let path: String
    let status: Int?
    let statusText: String?
    let error: String?
    let durationMs: Int?
    let bytesSent: Int64
    let bytesReceived: Int64
    let connection: String?
    let origin: String?
    let purpose: String?
    let account: String?
    let requestHeaders: [String: String]
    let responseHeaders: [String: String]
    let requestBody: String?
    let responseBody: String?

    init(event: NetworkAuditEvent, includeBody: Bool, timestamp: String) {
        id = event.id.uuidString
        time = timestamp
        kind = event.kind.rawValue
        direction = event.direction.rawValue
        category = event.category.rawValue
        method = event.method
        url = event.url
        host = event.host
        path = event.path
        status = event.statusCode
        statusText = event.statusText
        error = event.errorDescription
        durationMs = event.duration.map { Int(($0 * 1000).rounded()) }
        bytesSent = event.bytesSent
        bytesReceived = event.bytesReceived
        connection = event.connection
        origin = event.origin
        purpose = event.purpose
        account = event.accountName
        requestHeaders = Dictionary(event.requestHeaders.map { ($0.name, $0.value) }, uniquingKeysWith: { "\($0), \($1)" })
        responseHeaders = Dictionary(event.responseHeaders.map { ($0.name, $0.value) }, uniquingKeysWith: { "\($0), \($1)" })
        requestBody = includeBody ? event.requestBody.text : nil
        responseBody = includeBody ? event.responseBody.text : nil
    }
}

// MARK: - HAR shape

private enum HAR {
    struct Log: Encodable { let log: LogBody }
    struct LogBody: Encodable {
        let version: String
        let creator: Creator
        let entries: [Entry]
    }
    struct Creator: Encodable {
        let name: String
        let version: String
    }
    struct Entry: Encodable {
        let startedDateTime: String
        let time: Double
        let request: Request
        let response: Response
        let cache: Empty
        let timings: Timings
        let comment: String
    }
    struct Request: Encodable {
        let method: String
        let url: String
        let httpVersion: String
        let headers: [NameValue]
        let queryString: [NameValue]
        let cookies: [NameValue]
        let headersSize: Int
        let bodySize: Int64
        let postData: PostData?
    }
    struct Response: Encodable {
        let status: Int
        let statusText: String
        let httpVersion: String
        let headers: [NameValue]
        let cookies: [NameValue]
        let content: Content
        let redirectURL: String
        let headersSize: Int
        let bodySize: Int64
    }
    struct NameValue: Encodable {
        let name: String
        let value: String
    }
    struct PostData: Encodable {
        let mimeType: String
        let text: String
    }
    struct Content: Encodable {
        let size: Int64
        let mimeType: String
        let text: String?
    }
    struct Timings: Encodable {
        let send: Double
        let wait: Double
        let receive: Double
    }
    struct Empty: Encodable {}
}

// MARK: - Status / formatting

enum NetworkAuditStatus {

    /// Standard HTTP reason phrases (protocol constants, not localized).
    static func reasonPhrase(_ code: Int) -> String {
        switch code {
        case 200: return "OK"
        case 201: return "Created"
        case 202: return "Accepted"
        case 204: return "No Content"
        case 301: return "Moved Permanently"
        case 302: return "Found"
        case 304: return "Not Modified"
        case 307: return "Temporary Redirect"
        case 308: return "Permanent Redirect"
        case 400: return "Bad Request"
        case 401: return "Unauthorized"
        case 403: return "Forbidden"
        case 404: return "Not Found"
        case 409: return "Conflict"
        case 410: return "Gone"
        case 422: return "Unprocessable Content"
        case 429: return "Too Many Requests"
        case 500: return "Internal Server Error"
        case 502: return "Bad Gateway"
        case 503: return "Service Unavailable"
        case 504: return "Gateway Timeout"
        default: return HTTPURLResponse.localizedString(forStatusCode: code).capitalized
        }
    }

    /// "200 OK", "Copied", or the transport error.
    static func title(for event: NetworkAuditEvent) -> String {
        if let code = event.statusCode {
            return "\(code) \(reasonPhrase(code))"
        }
        if let text = event.statusText { return text }
        if event.errorDescription != nil {
            return String(localized: "Failed", comment: "Network audit: status of a request that got no response.")
        }
        return "—"
    }

    static func title(for summary: NetworkAuditEventSummary) -> String {
        if let code = summary.statusCode {
            return code >= 400 ? "\(code) \(reasonPhrase(code))" : "\(code)"
        }
        if let text = summary.statusText { return text }
        return String(localized: "Failed", comment: "Network audit: status of a request that got no response.")
    }
}

enum NetworkAuditFormatting {
    static func bytes(_ count: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowsNonnumericFormatting = false
        return formatter.string(fromByteCount: count)
    }
}
