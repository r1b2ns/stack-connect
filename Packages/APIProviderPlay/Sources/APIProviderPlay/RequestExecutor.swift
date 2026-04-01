import Foundation

// MARK: - Response

/// The result type delivered from a successful URLRequest.
public struct Response<T> {
    public typealias StatusCode = Int

    public let requestURL: URL?
    public let statusCode: Int
    public let data: T?
    public let headers: [AnyHashable: Any]

    public init(requestURL: URL?, statusCode: StatusCode, data: T?, headers: [AnyHashable: Any] = [:]) {
        self.requestURL = requestURL
        self.statusCode = statusCode
        self.data = data
        self.headers = headers
    }
}

// MARK: - RequestExecutor

/// Protocol abstraction for URLRequest execution.
public protocol RequestExecutor {
    func execute(_ urlRequest: URLRequest, completion: @escaping (Result<Response<Data>, Swift.Error>) -> Void)
}

// MARK: - DefaultRequestExecutor

/// URLSession-based concrete implementation.
public final class DefaultRequestExecutor: RequestExecutor {

    enum Error: Swift.Error {
        case unknownResponseType
    }

    private let urlSession = URLSession(configuration: .default)

    public init() {}

    public func execute(_ urlRequest: URLRequest, completion: @escaping (Result<Response<Data>, Swift.Error>) -> Void) {
        urlSession.dataTask(with: urlRequest) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            guard let httpResponse = response as? HTTPURLResponse else {
                completion(.failure(Error.unknownResponseType))
                return
            }
            completion(.success(.init(
                requestURL: httpResponse.url,
                statusCode: httpResponse.statusCode,
                data: data,
                headers: httpResponse.allHeaderFields
            )))
        }.resume()
    }
}
