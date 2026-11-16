#if DEBUG
import Foundation

/// Network guard of fake data mode, registered on `URLSession.shared`.
///
/// - `https://media.fakedata.example/…` (fake icons / screenshots) is answered
///   with a PNG rendered by `FakeMedia`.
/// - Every other http(s) request is refused with `notConnectedToInternet` and
///   logged, so a path that still reaches for the real network shows up in the
///   console instead of silently talking to a real account.
final class FakeNetworkURLProtocol: URLProtocol, @unchecked Sendable {

    override class func canInit(with request: URLRequest) -> Bool {
        guard let scheme = request.url?.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        if let png = FakeMedia.pngData(for: url),
           let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1",
                                          headerFields: ["Content-Type": "image/png", "Content-Length": "\(png.count)"]) {
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .allowed)
            client?.urlProtocol(self, didLoad: png)
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        Log.print.warning("[FakeData] Blocked network request to \(url.host ?? "?", privacy: .public)\(url.path, privacy: .public)")
        client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
    }

    override func stopLoading() {}
}
#endif
