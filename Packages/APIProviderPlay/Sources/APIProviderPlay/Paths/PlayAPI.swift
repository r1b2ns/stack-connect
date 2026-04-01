import Foundation

/// Root entry point for Google Play Developer API endpoints.
///
/// Usage:
/// ```swift
/// let endpoint = PlayAPI.v3.applications("com.example.app").edits.insert()
/// let response = try await provider.request(endpoint)
/// ```
public enum PlayAPI {
    public static let v3 = V3(path: "/androidpublisher/v3")
}

// MARK: - V3

public struct V3 {
    public let path: String

    /// Access a specific application by package name.
    public func applications(_ packageName: String) -> Application {
        Application(path: path + "/applications/\(packageName)")
    }

    /// Access reviews for a specific application.
    public func reviews(_ packageName: String) -> Reviews {
        Reviews(path: path + "/applications/\(packageName)/reviews")
    }
}
