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

    private let configuration: FirebaseConfiguration
    private let authenticator: FirebaseAuthenticator
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
    public init(
        configuration: FirebaseConfiguration,
        requestExecutor: RequestExecutor = DefaultRequestExecutor()
    ) {
        self.configuration = configuration
        self.requestExecutor = requestExecutor
        self.authenticator = FirebaseAuthenticator(configuration: configuration)
        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
    }

    // MARK: - Request (Void)

    /// Performs a request that expects no response body.
    public func request(_ endpoint: Request<Void>) async throws {
        let urlRequest = try await authenticatedRequest(for: endpoint)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Swift.Error>) in
            requestExecutor.execute(urlRequest) { result in
                switch result {
                case .success(let response):
                    guard 200..<300 ~= response.statusCode else {
                        let errorResponse = self.decodeError(from: response.data)
                        continuation.resume(throwing: Error.requestFailure(response.statusCode, errorResponse, response.requestURL))
                        return
                    }
                    continuation.resume()
                case .failure(let error):
                    continuation.resume(throwing: Error.requestExecutorError(error))
                }
            }
        }
    }

    // MARK: - Request (Decodable with Headers)

    /// Performs a request and returns the decoded response along with response headers.
    public func requestWithHeaders<T: Decodable>(_ endpoint: Request<T>) async throws -> (T, [AnyHashable: Any]) {
        let urlRequest = try await authenticatedRequest(for: endpoint)
        return try await withCheckedThrowingContinuation { continuation in
            requestExecutor.execute(urlRequest) { result in
                switch result {
                case .success(let response):
                    guard let data = response.data, 200..<300 ~= response.statusCode else {
                        let errorResponse = self.decodeError(from: response.data)
                        continuation.resume(throwing: Error.requestFailure(response.statusCode, errorResponse, response.requestURL))
                        return
                    }
                    do {
                        let decoded = try Self.jsonDecoder.decode(T.self, from: data)
                        continuation.resume(returning: (decoded, response.headers))
                    } catch {
                        continuation.resume(throwing: Error.decodingError(error, data))
                    }
                case .failure(let error):
                    continuation.resume(throwing: Error.requestExecutorError(error))
                }
            }
        }
    }

    // MARK: - Request (Decodable)

    /// Performs a request and decodes the response.
    public func request<T: Decodable>(_ endpoint: Request<T>) async throws -> T {
        let urlRequest = try await authenticatedRequest(for: endpoint)
        return try await withCheckedThrowingContinuation { continuation in
            requestExecutor.execute(urlRequest) { result in
                switch result {
                case .success(let response):
                    guard let data = response.data, 200..<300 ~= response.statusCode else {
                        let errorResponse = self.decodeError(from: response.data)
                        continuation.resume(throwing: Error.requestFailure(response.statusCode, errorResponse, response.requestURL))
                        return
                    }
                    do {
                        let decoded = try Self.jsonDecoder.decode(T.self, from: data)
                        continuation.resume(returning: decoded)
                    } catch {
                        continuation.resume(throwing: Error.decodingError(error, data))
                    }
                case .failure(let error):
                    continuation.resume(throwing: Error.requestExecutorError(error))
                }
            }
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
        } catch {
            throw Error.requestGeneration
        }
    }

    private func decodeError(from data: Data?) -> ErrorResponse? {
        guard let data else { return nil }
        return try? Self.jsonDecoder.decode(ErrorResponse.self, from: data)
    }
}
