import Foundation

/// Provides access to the Firebase Management REST API.
///
/// Usage:
/// ```swift
/// let jsonData = try Data(contentsOf: serviceAccountFileURL)
/// let config = try FirebaseConfiguration(serviceAccountJSON: jsonData)
/// let provider = APIProviderFirebase(configuration: config)
/// let projects = try await provider.request(FirebaseAPI.v1beta1.projects.get())
/// ```
public final class APIProviderFirebase: @unchecked Sendable {

    // MARK: - Error

    public enum Error: Swift.Error, LocalizedError {
        case requestGeneration
        case unknownResponseType
        case requestFailure(StatusCode, ErrorResponse?, URL?)
        case decodingError(Swift.Error, Data)
        case requestExecutorError(Swift.Error)

        public var errorDescription: String? {
            switch self {
            case .requestGeneration:
                return "Failed to generate request."
            case .unknownResponseType:
                return "Unknown response type."
            case .requestFailure(let statusCode, let errorResponse, let url):
                let urlStr = url?.absoluteString ?? ""
                if let errorResponse {
                    return "Request \(urlStr) failed (\(statusCode)): \(errorResponse)"
                }
                return "Request \(urlStr) failed (\(statusCode))."
            case .decodingError(let error, let data):
                if let body = String(data: data, encoding: .utf8) {
                    return "Decoding failed:\n\(body)\nError: \(error)"
                }
                return "Failed to decode response."
            case .requestExecutorError(let error):
                return "Request execution failed: \(error)"
            }
        }
    }

    public typealias StatusCode = Int

    // MARK: - Properties

    /// The service account, or `nil` for a provider authenticated with a
    /// user's own OAuth token (`init(authenticator:requestExecutor:)`).
    private let configuration: FirebaseConfiguration?
    private let authenticator: RequestAuthenticating
    private let requestExecutor: RequestExecutor
    private let encoder: JSONEncoder

    /// Shared JSON decoder for response parsing.
    public static let jsonDecoder: JSONDecoder = {
        let decoder = JSONDecoder()

        // Google APIs use ISO 8601 timestamps with various formats
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.calendar = Calendar(identifier: .iso8601)

        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateStr = try container.decode(String.self)

            formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX"
            if let date = formatter.date(from: dateStr) { return date }

            formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssXXXXX"
            if let date = formatter.date(from: dateStr) { return date }

            formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
            if let date = formatter.date(from: dateStr) { return date }

            formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
            if let date = formatter.date(from: dateStr) { return date }

            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = iso.date(from: dateStr) { return date }

            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Cannot decode date: \(dateStr)"
            )
        }

        return decoder
    }()

    // MARK: - Init

    /// Creates a new Firebase API provider.
    ///
    /// - Parameters:
    ///   - configuration: Firebase service account configuration.
    ///   - requestExecutor: Optional custom request executor. Defaults to URLSession.
    public convenience init(
        configuration: FirebaseConfiguration,
        requestExecutor: RequestExecutor = DefaultRequestExecutor()
    ) {
        self.init(
            configuration: configuration,
            requestExecutor: requestExecutor,
            authenticator: FirebaseAuthenticator(configuration: configuration)
        )
    }

    /// Creates a provider with a custom authenticator — the seam for hosts that
    /// serve the API in-process (e.g. a demo / fake-data mode) and must never
    /// exchange the service-account JWT with Google's token endpoint.
    ///
    /// - Parameters:
    ///   - configuration: Firebase service account configuration.
    ///   - requestExecutor: Executes the authenticated requests.
    ///   - authenticator: Adds credentials to every outgoing request.
    public init(
        configuration: FirebaseConfiguration,
        requestExecutor: RequestExecutor,
        authenticator: RequestAuthenticating
    ) {
        self.configuration = configuration
        self.requestExecutor = requestExecutor
        self.authenticator = authenticator
        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
    }

    /// Creates a provider authenticated by `authenticator` alone, without a
    /// service account: e.g. a user's own Google OAuth login, whose access
    /// token the authenticator adds to every request.
    ///
    /// - Parameters:
    ///   - authenticator: Adds credentials to every outgoing request. Errors it
    ///     throws that conform to `RequestAuthenticationError` reach the caller
    ///     unchanged; any other error becomes `Error.requestGeneration`.
    ///   - requestExecutor: Executes the authenticated requests.
    public init(
        authenticator: RequestAuthenticating,
        requestExecutor: RequestExecutor = DefaultRequestExecutor()
    ) {
        self.configuration = nil
        self.requestExecutor = requestExecutor
        self.authenticator = authenticator
        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
    }

    // MARK: - Request (Void)

    /// Performs a request that expects no response body.
    public func request(_ endpoint: Request<Void>) async throws {
        let response = try await perform(endpoint)
        guard 200..<300 ~= response.statusCode else {
            throw Error.requestFailure(response.statusCode, decodeError(from: response.data), response.requestURL)
        }
    }

    // MARK: - Request (Decodable with Headers)

    /// Performs a request and returns the decoded response along with response headers.
    public func requestWithHeaders<T: Decodable>(_ endpoint: Request<T>) async throws -> (T, [AnyHashable: Any]) {
        let response = try await perform(endpoint)
        return (try decodeBody(T.self, from: response), response.headers)
    }

    // MARK: - Request (Decodable)

    /// Performs a request and decodes the response.
    public func request<T: Decodable>(_ endpoint: Request<T>) async throws -> T {
        let response = try await perform(endpoint)
        return try decodeBody(T.self, from: response)
    }

    // MARK: - Execution

    /// Authenticates and executes `endpoint`. An HTTP 401 is retried once,
    /// re-authenticated, when the authenticator is a `RequestReauthenticating`
    /// that asks for it (e.g. a user access token revoked before it expired).
    private func perform<T>(_ endpoint: Request<T>) async throws -> Response<Data> {
        let response = try await execute(try await authenticatedRequest(for: endpoint))
        guard response.statusCode == 401,
              let reauthenticating = authenticator as? RequestReauthenticating,
              await reauthenticating.shouldRetryAfterUnauthorized() else {
            return response
        }
        // A second 401 is returned as is: no retry loop.
        return try await execute(try await authenticatedRequest(for: endpoint))
    }

    private func execute(_ urlRequest: URLRequest) async throws -> Response<Data> {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Response<Data>, Swift.Error>) in
            requestExecutor.execute(urlRequest) { result in
                switch result {
                case .success(let response):
                    continuation.resume(returning: response)
                case .failure(let error):
                    continuation.resume(throwing: Error.requestExecutorError(error))
                }
            }
        }
    }

    private func decodeBody<T: Decodable>(_ type: T.Type, from response: Response<Data>) throws -> T {
        guard let data = response.data, 200..<300 ~= response.statusCode else {
            throw Error.requestFailure(response.statusCode, decodeError(from: response.data), response.requestURL)
        }
        do {
            return try Self.jsonDecoder.decode(T.self, from: data)
        } catch {
            throw Error.decodingError(error, data)
        }
    }

    // MARK: - Private

    private func authenticatedRequest<T>(for endpoint: Request<T>) async throws -> URLRequest {
        do {
            var urlRequest = try endpoint.asURLRequest(encoder: encoder)
            // Merge custom headers from endpoint
            if let customHeaders = endpoint.headers {
                for (key, value) in customHeaders {
                    urlRequest.setValue(value, forHTTPHeaderField: key)
                }
            }
            return try await authenticator.adapt(urlRequest)
        } catch let error as RequestAuthenticationError {
            // An authenticator that wants its cause seen (e.g. an expired
            // user login) opts in; everything else keeps the historic wrapping.
            throw error
        } catch {
            throw Error.requestGeneration
        }
    }

    private func decodeError(from data: Data?) -> ErrorResponse? {
        guard let data else { return nil }
        return try? Self.jsonDecoder.decode(ErrorResponse.self, from: data)
    }
}
