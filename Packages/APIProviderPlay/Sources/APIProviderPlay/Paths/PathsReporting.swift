import Foundation

private let reportingBaseURL = URL(string: "https://playdeveloperreporting.googleapis.com")!

// MARK: - Reporting Apps

/// Access the Play Developer Reporting API to search accessible apps.
public struct ReportingApps {
    public let path: String

    /// Search for apps accessible by the authenticated service account.
    ///
    /// `GET https://playdeveloperreporting.googleapis.com/v1beta1/apps:search`
    ///
    /// - Parameters:
    ///   - pageSize: Max number of apps to return (default 50, max 1000).
    ///   - pageToken: Pagination token from a previous response.
    public func search(
        pageSize: Int? = nil,
        pageToken: String? = nil
    ) -> Request<SearchPlayAppsResponse> {
        var query: [(String, String?)] = []
        if let pageSize { query.append(("pageSize", String(pageSize))) }
        if let pageToken { query.append(("pageToken", pageToken)) }

        return Request(
            path: path + ":search",
            method: "GET",
            query: query.isEmpty ? nil : query,
            id: "reportingApps_search",
            customBaseURL: reportingBaseURL
        )
    }
}
