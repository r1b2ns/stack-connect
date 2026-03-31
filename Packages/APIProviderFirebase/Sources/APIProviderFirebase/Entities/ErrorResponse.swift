import Foundation

/// Standard Google API error response.
public struct ErrorResponse: Decodable, CustomStringConvertible {
    public let error: GoogleAPIError?

    public struct GoogleAPIError: Decodable {
        public let code: Int?
        public let message: String?
        public let status: String?
        public let errors: [ErrorDetail]?
        public let details: [ErrorDetailInfo]?
    }

    public struct ErrorDetail: Decodable {
        public let message: String?
        public let domain: String?
        public let reason: String?
    }

    /// Captures `type.googleapis.com/google.rpc.ErrorInfo` entries from `details`.
    public struct ErrorDetailInfo: Decodable {
        public let type: String?
        public let reason: String?
        public let domain: String?
        public let metadata: Metadata?

        enum CodingKeys: String, CodingKey {
            case type = "@type"
            case reason
            case domain
            case metadata
        }

        public struct Metadata: Decodable {
            public let service: String?
            public let activationUrl: String?
            public let consumer: String?
        }
    }

    public var description: String {
        if let error {
            return "[\(error.code ?? 0)] \(error.message ?? "Unknown error")"
        }
        return "Unknown error"
    }

    /// Returns the activation URL if the error is `SERVICE_DISABLED`.
    public var activationURL: String? {
        error?.details?.compactMap(\.metadata?.activationUrl).first
    }

    /// Whether this error is specifically about a disabled API.
    public var isServiceDisabled: Bool {
        error?.details?.contains(where: { $0.reason == "SERVICE_DISABLED" }) == true
    }
}
