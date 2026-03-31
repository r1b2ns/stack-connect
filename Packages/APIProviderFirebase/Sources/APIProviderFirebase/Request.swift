import Foundation

// MARK: - AnyEncodable

struct AnyEncodable: Encodable {
    private let value: Encodable

    init(_ value: Encodable) {
        self.value = value
    }

    func encode(to encoder: Encoder) throws {
        try value.encode(to: encoder)
    }
}

// MARK: - Request

/// A generic HTTP request descriptor for the Firebase Management API.
public struct Request<Response> {
    public var method: String
    public var path: String
    public var query: [(String, String?)]?
    var body: AnyEncodable?
    public var headers: [String: String]?
    public var id: String?
    public var customBaseURL: URL?

    public init(
        path: String,
        method: String,
        query: [(String, String?)]? = nil,
        headers: [String: String]? = nil,
        id: String? = nil,
        customBaseURL: URL? = nil
    ) {
        self.method = method
        self.path = path
        self.query = query
        self.headers = headers
        self.id = id
        self.customBaseURL = customBaseURL
    }

    public init<U: Encodable>(
        path: String,
        method: String,
        query: [(String, String?)]? = nil,
        body: U?,
        headers: [String: String]? = nil,
        id: String? = nil,
        customBaseURL: URL? = nil
    ) {
        self.method = method
        self.path = path
        self.query = query
        self.body = body.map(AnyEncodable.init)
        self.headers = headers
        self.id = id
        self.customBaseURL = customBaseURL
    }
}

// MARK: - URLRequest conversion

extension Request {

    static var baseURL: URL {
        URL(string: "https://firebase.googleapis.com")!
    }

    private func makeURL(path: String, query: [(String, String?)]?) throws -> URL {
        let base = customBaseURL ?? Self.baseURL
        let url = base.appendingPathComponent(path)
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw URLError(.badURL)
        }
        if let query = query, !query.isEmpty {
            components.queryItems = query.map(URLQueryItem.init)
        }
        guard let url = components.url else {
            throw URLError(.badURL)
        }
        return url
    }

    /// Converts this request descriptor into a URLRequest.
    public func asURLRequest(encoder: JSONEncoder) throws -> URLRequest {
        let url = try makeURL(path: path, query: query)
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = method

        if let body = body {
            urlRequest.httpBody = try encoder.encode(body)
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        return urlRequest
    }
}
