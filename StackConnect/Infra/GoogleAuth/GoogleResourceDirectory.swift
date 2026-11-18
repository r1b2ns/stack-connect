import Foundation
import StackProtocols

/// Something a Google login can see and the user may add as an account (plan G5).
struct GoogleAccessibleResource: Identifiable, Equatable, Hashable, Sendable {
    /// Play: the package name. Firebase: the project ID.
    let id: String
    let title: String
    /// Play: the package name. Firebase: the project ID (when it differs from the title).
    let subtitle: String?
}

/// Lists what a Google login can access, with the user's own token.
protocol GoogleResourceListing: Sendable {
    /// Play Developer Reporting `apps:search`: every Play app the user can see.
    func playApps(loginId: String) async throws -> [GoogleAccessibleResource]
    /// Firebase Management `projects.list`: every Firebase project the user can see.
    func firebaseProjects(loginId: String) async throws -> [GoogleAccessibleResource]
}

/// Live implementation over `GoogleHTTPClient`. Follows `nextPageToken` up to
/// `maxPages` pages, so a huge organization can't loop forever.
///
/// Errors are `GoogleAuthError`s: `SERVICE_DISABLED` (an API not enabled in
/// StackConnect's Cloud project) and quota errors are logged here with
/// Google's machine-readable status and reasons only.
struct GoogleResourceDirectory: GoogleResourceListing {

    static let pageSize = 100
    static let maxPages = 20

    private let tokens: GoogleAccessTokenProviding
    private let http: GoogleHTTPClient

    init(tokens: GoogleAccessTokenProviding, http: GoogleHTTPClient = URLSessionGoogleHTTPClient()) {
        self.tokens = tokens
        self.http = http
    }

    func playApps(loginId: String) async throws -> [GoogleAccessibleResource] {
        let pages = try await fetchPages(baseURL: GoogleOAuthEndpoint.playApps, loginId: loginId, label: "Play apps")
        let resources = pages.flatMap { page -> [GoogleAccessibleResource] in
            let apps = page["apps"] as? [[String: Any]] ?? []
            return apps.compactMap { app in
                guard let packageName = app["packageName"] as? String, !packageName.isEmpty else { return nil }
                let displayName = (app["displayName"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                return GoogleAccessibleResource(id: packageName, title: displayName ?? packageName, subtitle: packageName)
            }
        }
        Log.print.info("[GoogleAuth] Listed \(resources.count) Play app(s)")
        return Self.sorted(resources)
    }

    func firebaseProjects(loginId: String) async throws -> [GoogleAccessibleResource] {
        let pages = try await fetchPages(baseURL: GoogleOAuthEndpoint.firebaseProjects, loginId: loginId, label: "Firebase projects")
        let resources = pages.flatMap { page -> [GoogleAccessibleResource] in
            let projects = page["results"] as? [[String: Any]] ?? []
            return projects.compactMap { project in
                // Deleted projects can still be listed for 30 days.
                if let state = project["state"] as? String, state == "DELETED" { return nil }
                guard let projectId = project["projectId"] as? String, !projectId.isEmpty else { return nil }
                let displayName = (project["displayName"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                return GoogleAccessibleResource(
                    id: projectId,
                    title: displayName ?? projectId,
                    subtitle: displayName == projectId ? nil : projectId
                )
            }
        }
        Log.print.info("[GoogleAuth] Listed \(resources.count) Firebase project(s)")
        return Self.sorted(resources)
    }

    // MARK: - Private

    private func fetchPages(baseURL: URL, loginId: String, label: String) async throws -> [[String: Any]] {
        var pages: [[String: Any]] = []
        var pageToken: String?
        repeat {
            let url = Self.pageURL(baseURL: baseURL, pageToken: pageToken)
            let token = try await tokens.accessToken(forLogin: loginId)
            let response: GoogleHTTPResponse
            do {
                response = try await http.send(GoogleOAuthTokenClient.bearerRequest(url: url, accessToken: token))
            } catch let error as URLError {
                throw GoogleAuthError.network(error.code)
            }
            guard response.isSuccess else {
                let summary = GoogleAPIErrorSummary.parse(response.data)
                Log.print.error("[GoogleAuth] Listing \(label, privacy: .public) failed: HTTP \(response.statusCode, privacy: .public) \(summary?.logLine ?? "", privacy: .public)")
                throw GoogleAuthError.http(statusCode: response.statusCode, summary: summary)
            }
            guard let page = (try? JSONSerialization.jsonObject(with: response.data)) as? [String: Any] else {
                throw GoogleAuthError.invalidTokenResponse
            }
            pages.append(page)
            pageToken = (page["nextPageToken"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        } while pageToken != nil && pages.count < Self.maxPages
        return pages
    }

    static func pageURL(baseURL: URL, pageToken: String?) -> URL {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        var items = [URLQueryItem(name: "pageSize", value: String(pageSize))]
        if let pageToken {
            items.append(URLQueryItem(name: "pageToken", value: pageToken))
        }
        components?.queryItems = items
        return components?.url ?? baseURL
    }

    private static func sorted(_ resources: [GoogleAccessibleResource]) -> [GoogleAccessibleResource] {
        resources.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }
}
