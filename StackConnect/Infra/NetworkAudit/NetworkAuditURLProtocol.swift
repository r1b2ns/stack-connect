import Foundation
import Network
import StackProtocols

// MARK: - Request tagging

/// Lets a call site say why a request is made. The tags ride on the
/// `URLRequest` as `URLProtocol` properties: they are never sent to the server.
enum NetworkAuditRequestTag {

    static let originKey = "StackConnect.NetworkAudit.origin"
    static let purposeKey = "StackConnect.NetworkAudit.purpose"
    static let accountKey = "StackConnect.NetworkAudit.account"

    /// A copy of `request` carrying the given tags.
    static func tagged(_ request: URLRequest, origin: String? = nil, purpose: String? = nil, account: String? = nil) -> URLRequest {
        guard let mutable = (request as NSURLRequest).mutableCopy() as? NSMutableURLRequest else { return request }
        if let origin { URLProtocol.setProperty(origin, forKey: originKey, in: mutable) }
        if let purpose { URLProtocol.setProperty(purpose, forKey: purposeKey, in: mutable) }
        if let account { URLProtocol.setProperty(account, forKey: accountKey, in: mutable) }
        return mutable as URLRequest
    }

    static func tags(of request: URLRequest) -> (origin: String?, purpose: String?, account: String?) {
        (
            URLProtocol.property(forKey: originKey, in: request) as? String,
            URLProtocol.property(forKey: purposeKey, in: request) as? String,
            URLProtocol.property(forKey: accountKey, in: request) as? String
        )
    }
}

// MARK: - URLProtocol

/// Records every http(s) request of the sessions it is installed on
/// (`NetworkAuditSessionInstaller`) and forwards it, unchanged, through a
/// private session (`NetworkAuditForwarder`).
///
/// A forwarded request carries `handledKey`, so it is never recorded twice:
/// not by this protocol on the private session, and not when another
/// recording protocol (netfox in DEBUG) re-runs it through a session built
/// from the swizzled default configuration.
final class NetworkAuditURLProtocol: URLProtocol, @unchecked Sendable {

    static let handledKey = "StackConnect.NetworkAudit.handled"

    /// Where exchanges go. `nil` turns recording off (`canInit` answers `false`).
    nonisolated(unsafe) static var sink: NetworkAuditExchangeSink?

    private let lock = NSLock()
    private var forwardedTask: URLSessionDataTask?
    private var clientRunLoop: CFRunLoop?
    private var clientModes: [CFString] = []
    private var startedAt = Date()
    private var sentBody: Data?
    private var response: HTTPURLResponse?
    private var receivedData = Data()
    private var receivedLength: Int64 = 0
    private var metrics: URLSessionTaskMetrics?

    // MARK: - Registration

    override class func canInit(with request: URLRequest) -> Bool {
        guard sink != nil,
              let scheme = request.url?.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else { return false }
        return URLProtocol.property(forKey: handledKey, in: request) == nil
    }

    override class func canInit(with task: URLSessionTask) -> Bool {
        if task is URLSessionStreamTask || task is URLSessionWebSocketTask { return false }
        guard let request = task.currentRequest ?? task.originalRequest else { return false }
        return canInit(with: request)
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    /// The request to run on the private session: marked as handled, with a
    /// streamed body read into `httpBody` so it can be recorded and re-sent.
    static func forwardedRequest(for request: URLRequest) -> URLRequest {
        var forwarded = request
        if forwarded.httpBody == nil, let stream = forwarded.httpBodyStream {
            // Setting `httpBody` also drops the stream (they are exclusive).
            forwarded.httpBody = Self.read(stream)
        }
        guard let mutable = (forwarded as NSURLRequest).mutableCopy() as? NSMutableURLRequest else { return forwarded }
        URLProtocol.setProperty(true, forKey: handledKey, in: mutable)
        return mutable as URLRequest
    }

    // MARK: - Loading

    override func startLoading() {
        let forwarded = Self.forwardedRequest(for: request)
        lock.lock()
        clientRunLoop = CFRunLoopGetCurrent()
        var modes: [CFString] = [CFRunLoopMode.commonModes.rawValue]
        if let current = RunLoop.current.currentMode, current != .common {
            modes.append(current.rawValue as CFString)
        }
        clientModes = modes
        startedAt = Date()
        sentBody = forwarded.httpBody
        lock.unlock()

        let task = NetworkAuditForwarder.shared.start(forwarded, for: self)
        lock.lock()
        forwardedTask = task
        lock.unlock()
    }

    override func stopLoading() {
        lock.lock()
        let task = forwardedTask
        forwardedTask = nil
        lock.unlock()
        task?.cancel()
    }

    // MARK: - Forwarder callbacks (private session's delegate queue)

    func forwarderDidReceive(_ response: URLResponse) {
        lock.lock()
        self.response = response as? HTTPURLResponse
        lock.unlock()
        onClientThread { [self] in
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        }
    }

    func forwarderDidReceive(_ data: Data) {
        lock.lock()
        receivedLength += Int64(data.count)
        if receivedData.count + data.count <= NetworkAuditRecorder.maxMaskableBodyBytes {
            receivedData.append(data)
        }
        lock.unlock()
        onClientThread { [self] in
            client?.urlProtocol(self, didLoad: data)
        }
    }

    func forwarderDidCollect(_ metrics: URLSessionTaskMetrics) {
        lock.lock()
        self.metrics = metrics
        lock.unlock()
    }

    func forwarderDidComplete(task: URLSessionTask, error: Error?) {
        let exchange = makeExchange(task: task, error: error)
        onClientThread { [self] in
            if let error {
                client?.urlProtocol(self, didFailWithError: error)
            } else {
                client?.urlProtocolDidFinishLoading(self)
            }
        }
        if let exchange {
            Self.sink?.record(exchange)
        }
    }

    // MARK: - Private

    /// URL loading expects the client to be called on the thread (run loop)
    /// that called `startLoading`.
    private func onClientThread(_ block: @escaping () -> Void) {
        lock.lock()
        let runLoop = clientRunLoop
        let modes = clientModes
        lock.unlock()
        guard let runLoop else {
            block()
            return
        }
        CFRunLoopPerformBlock(runLoop, modes as CFArray, block)
        CFRunLoopWakeUp(runLoop)
    }

    private func makeExchange(task: URLSessionTask, error: Error?) -> NetworkAuditExchange? {
        lock.lock()
        defer { lock.unlock() }
        guard let url = request.url else { return nil }

        let transaction = metrics?.transactionMetrics.last
        let sentRequest = transaction?.request ?? task.currentRequest ?? request
        let requestHeaders = Self.fields(sentRequest.allHTTPHeaderFields ?? [:])
        let responseHeaders = Self.fields(response?.allHeaderFields ?? [:])
        let tags = NetworkAuditRequestTag.tags(of: request)
        let wire = metrics.map(Self.wireBytes)

        let isOverflow = receivedLength > Int64(receivedData.count)
        return NetworkAuditExchange(
            source: .urlSession,
            startedAt: startedAt,
            duration: Date().timeIntervalSince(startedAt),
            method: request.httpMethod ?? "GET",
            url: url,
            requestHeaders: requestHeaders,
            requestBody: sentBody,
            requestBodyLength: Int64(sentBody?.count ?? 0),
            statusCode: response?.statusCode,
            responseHeaders: responseHeaders,
            responseBody: isOverflow ? nil : receivedData,
            responseBodyLength: receivedLength,
            wireBytesSent: wire?.sent,
            wireBytesReceived: wire?.received,
            tlsVersion: transaction.flatMap(Self.tlsVersion),
            httpVersion: transaction?.networkProtocolName.map(Self.httpVersion),
            errorDescription: error?.localizedDescription,
            origin: tags.origin,
            purpose: tags.purpose,
            accountName: tags.account
        )
    }

    private static func fields(_ headers: [AnyHashable: Any]) -> [NetworkAuditExchange.HeaderField] {
        headers.compactMap { key, value -> NetworkAuditExchange.HeaderField? in
            guard let name = key as? String else { return nil }
            return NetworkAuditExchange.HeaderField(name: name, value: "\(value)")
        }
        .sorted { $0.name.lowercased() < $1.name.lowercased() }
    }

    private static func fields(_ headers: [String: String]) -> [NetworkAuditExchange.HeaderField] {
        headers.map { NetworkAuditExchange.HeaderField(name: $0.key, value: $0.value) }
            .sorted { $0.name.lowercased() < $1.name.lowercased() }
    }

    private static func wireBytes(_ metrics: URLSessionTaskMetrics) -> (sent: Int64, received: Int64) {
        metrics.transactionMetrics.reduce((sent: Int64(0), received: Int64(0))) { total, transaction in
            (
                total.sent + transaction.countOfRequestHeaderBytesSent + transaction.countOfRequestBodyBytesSent,
                total.received + transaction.countOfResponseHeaderBytesReceived + transaction.countOfResponseBodyBytesReceived
            )
        }
    }

    static func tlsVersion(_ transaction: URLSessionTaskTransactionMetrics) -> String? {
        guard let version = transaction.negotiatedTLSProtocolVersion else { return nil }
        switch version {
        case .TLSv13: return "TLS 1.3"
        case .TLSv12: return "TLS 1.2"
        case .DTLSv12: return "DTLS 1.2"
        default: return "TLS"
        }
    }

    static func httpVersion(_ protocolName: String) -> String {
        switch protocolName.lowercased() {
        case "h2": return "HTTP/2"
        case "h3": return "HTTP/3"
        case "http/1.1": return "HTTP/1.1"
        case "http/1.0": return "HTTP/1.0"
        default: return protocolName.uppercased()
        }
    }

    private static func read(_ stream: InputStream) -> Data {
        var data = Data()
        stream.open()
        defer { stream.close() }
        let bufferSize = 16 * 1024
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: bufferSize)
            guard read > 0 else { break }
            data.append(buffer, count: read)
        }
        return data
    }
}

// MARK: - Forwarder

/// The private session that runs recorded requests for real. Its
/// configuration never contains `NetworkAuditURLProtocol` (and the requests
/// it runs are marked as handled anyway). It keeps the other protocol classes
/// of the default configuration, so netfox still sees the traffic in DEBUG.
///
/// Redirects are followed here; the client gets the final response.
final class NetworkAuditForwarder: NSObject, URLSessionDataDelegate, @unchecked Sendable {

    static let shared = NetworkAuditForwarder()

    private let lock = NSLock()
    private var handlers: [Int: NetworkAuditURLProtocol] = [:]
    private var session: URLSession?

    func start(_ request: URLRequest, for handler: NetworkAuditURLProtocol) -> URLSessionDataTask {
        let task = makeSessionIfNeeded().dataTask(with: request)
        lock.lock()
        handlers[task.taskIdentifier] = handler
        lock.unlock()
        task.resume()
        return task
    }

    private func makeSessionIfNeeded() -> URLSession {
        lock.lock()
        defer { lock.unlock() }
        if let session { return session }
        let configuration = URLSessionConfiguration.default
        configuration.protocolClasses = (configuration.protocolClasses ?? []).filter {
            ObjectIdentifier($0) != ObjectIdentifier(NetworkAuditURLProtocol.self)
        }
        let queue = OperationQueue()
        queue.name = "StackConnect.NetworkAudit.forwarder"
        queue.maxConcurrentOperationCount = 1
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: queue)
        self.session = session
        return session
    }

    private func handler(for task: URLSessionTask) -> NetworkAuditURLProtocol? {
        lock.lock()
        defer { lock.unlock() }
        return handlers[task.taskIdentifier]
    }

    private func removeHandler(for task: URLSessionTask) -> NetworkAuditURLProtocol? {
        lock.lock()
        defer { lock.unlock() }
        return handlers.removeValue(forKey: task.taskIdentifier)
    }

    // MARK: - URLSessionDataDelegate

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        handler(for: dataTask)?.forwarderDidReceive(response)
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        handler(for: dataTask)?.forwarderDidReceive(data)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        handler(for: task)?.forwarderDidCollect(metrics)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        removeHandler(for: task)?.forwarderDidComplete(task: task, error: error)
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        willCacheResponse proposedResponse: CachedURLResponse,
        completionHandler: @escaping (CachedURLResponse?) -> Void
    ) {
        completionHandler(proposedResponse)
    }
}
