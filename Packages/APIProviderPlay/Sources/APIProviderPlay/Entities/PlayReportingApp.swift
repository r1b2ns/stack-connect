import Foundation

// MARK: - Search Apps Response

/// Response from `GET playdeveloperreporting.googleapis.com/v1beta1/apps:search`
public struct SearchPlayAppsResponse: Decodable {
    public let apps: [PlayReportingApp]?
    public let nextPageToken: String?
}

// MARK: - Play Reporting App

/// An app accessible via the Play Developer Reporting API.
public struct PlayReportingApp: Decodable, Identifiable {
    /// Resource name: `apps/{app}`
    public let name: String?

    /// The package name (e.g. "com.example.app").
    public let packageName: String?

    /// The display name as configured in Play Console.
    public let displayName: String?

    public var id: String {
        packageName ?? name ?? UUID().uuidString
    }
}
