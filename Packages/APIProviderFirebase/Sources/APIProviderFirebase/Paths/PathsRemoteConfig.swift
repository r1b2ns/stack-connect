import Foundation

// MARK: - Remote Config Base URL

private let remoteConfigBaseURL = URL(string: "https://firebaseremoteconfig.googleapis.com")!

// MARK: - Remote Config Collection

public struct RemoteConfig {
    public let path: String

    /// Fetch the current Remote Config template for a project.
    ///
    /// `GET /v1/projects/{projectId}/remoteConfig`
    ///
    /// Returns the full template including parameters, conditions, and version metadata.
    /// The ETag is returned in the `ETag` response header and is required for updates.
    public func get() -> Request<RemoteConfigTemplate> {
        Request(
            path: path,
            method: "GET",
            headers: ["Accept-Encoding": "gzip"],
            id: "remoteConfig_get",
            customBaseURL: remoteConfigBaseURL
        )
    }

    /// Update (replace) the Remote Config template.
    ///
    /// `PUT /v1/projects/{projectId}/remoteConfig`
    ///
    /// You must provide the ETag from the last GET in the `If-Match` header.
    /// Use `If-Match: *` to force-overwrite (not recommended).
    ///
    /// - Parameters:
    ///   - template: The full template to write.
    ///   - etag: The ETag received from the last GET response.
    ///   - validateOnly: If true, validates without writing (dry run).
    public func put(
        _ template: RemoteConfigTemplate,
        etag: String,
        validateOnly: Bool = false
    ) -> Request<RemoteConfigTemplate> {
        var query: [(String, String?)] = []
        if validateOnly {
            query.append(("validate_only", "true"))
        }

        return Request(
            path: path,
            method: "PUT",
            query: query.isEmpty ? nil : query,
            body: template,
            headers: [
                "If-Match": etag,
                "Content-Type": "application/json; UTF-8"
            ],
            id: "remoteConfig_put",
            customBaseURL: remoteConfigBaseURL
        )
    }

    /// List all stored versions of the Remote Config template.
    ///
    /// `GET /v1/projects/{projectId}/remoteConfig:listVersions`
    public func listVersions(
        pageSize: Int? = nil,
        pageToken: String? = nil
    ) -> Request<ListRemoteConfigVersionsResponse> {
        var query: [(String, String?)] = []
        if let pageSize { query.append(("pageSize", String(pageSize))) }
        if let pageToken { query.append(("pageToken", pageToken)) }

        return Request(
            path: path + ":listVersions",
            method: "GET",
            query: query.isEmpty ? nil : query,
            id: "remoteConfig_listVersions",
            customBaseURL: remoteConfigBaseURL
        )
    }

    /// Roll back to a specific version of the Remote Config template.
    ///
    /// `POST /v1/projects/{projectId}/remoteConfig:rollback`
    public func rollback(to versionNumber: String) -> Request<RemoteConfigTemplate> {
        Request(
            path: path + ":rollback",
            method: "POST",
            body: RollbackRemoteConfigRequest(versionNumber: versionNumber),
            id: "remoteConfig_rollback",
            customBaseURL: remoteConfigBaseURL
        )
    }
}
