import Foundation

/// Provides access to the Google Play Developer REST API.
///
/// Usage:
/// ```swift
/// let jsonData = try Data(contentsOf: serviceAccountFileURL)
/// let config = try PlayConfiguration(serviceAccountJSON: jsonData)
/// let provider = APIProviderPlay(configuration: config)
/// let edit = try await provider.request(PlayAPI.v3.applications("com.example.app").edits.insert())
/// ```
public final class APIProviderPlay: @unchecked Sendable {

    // MARK: - Error

    public enum Error: Swift.Error, LocalizedError {
        case requestGeneration
        case unknownResponseType
        case requestFailure(StatusCode, PlayErrorResponse?, URL?)
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

    private let configuration: PlayConfiguration
    private let authenticator: PlayAuthenticator
    private let requestExecutor: RequestExecutor
    private let encoder: JSONEncoder

    /// Shared JSON decoder for response parsing.
    public static let jsonDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        return decoder
    }()

    // MARK: - Init

    public init(
        configuration: PlayConfiguration,
        requestExecutor: RequestExecutor = DefaultRequestExecutor()
    ) {
        self.configuration = configuration
        self.requestExecutor = requestExecutor
        self.authenticator = PlayAuthenticator(configuration: configuration)
        self.encoder = JSONEncoder()
    }

    // MARK: - Request (Void)

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

    // MARK: - Request (Decodable)

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

    private func decodeError(from data: Data?) -> PlayErrorResponse? {
        guard let data else { return nil }
        return try? Self.jsonDecoder.decode(PlayErrorResponse.self, from: data)
    }
}
