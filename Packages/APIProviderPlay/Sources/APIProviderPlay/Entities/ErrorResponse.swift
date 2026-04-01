import Foundation

/// Standard Google API error response.
public struct PlayErrorResponse: Decodable, CustomStringConvertible {
    public let error: GoogleAPIError?

    public struct GoogleAPIError: Decodable {
        public let code: Int?
        public let message: String?
        public let status: String?
        public let errors: [ErrorDetail]?
    }

    public struct ErrorDetail: Decodable {
        public let message: String?
        public let domain: String?
        public let reason: String?
    }

    public var description: String {
        if let error {
            return "[\(error.code ?? 0)] \(error.message ?? "Unknown error")"
        }
        return "Unknown error"
    }
}
