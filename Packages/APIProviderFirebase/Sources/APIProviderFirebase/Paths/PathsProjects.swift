import Foundation

// MARK: - Projects Collection

public struct Projects {
    public let path: String

    /// List all Firebase projects accessible by the caller.
    ///
    /// `GET v1beta1/projects`
    ///
    /// - Parameters:
    ///   - pageSize: Maximum number of projects to return.
    ///   - pageToken: Pagination token from a previous response.
    /// - Returns: A request that resolves to `ListFirebaseProjectsResponse`.
    public func get(
        pageSize: Int? = nil,
        pageToken: String? = nil
    ) -> Request<ListFirebaseProjectsResponse> {
        var query: [(String, String?)] = []
        if let pageSize {
            query.append(("pageSize", String(pageSize)))
        }
        if let pageToken {
            query.append(("pageToken", pageToken))
        }

        return Request(
            path: path,
            method: "GET",
            query: query.isEmpty ? nil : query,
            id: "projects_list"
        )
    }

    /// Access a specific project by ID.
    public func id(_ projectId: String) -> ProjectWithID {
        ProjectWithID(path: path + "/\(projectId)")
    }
}

// MARK: - Single Project

public struct ProjectWithID {
    public let path: String

    /// Get a single Firebase project.
    ///
    /// `GET v1beta1/projects/{projectId}`
    public func get() -> Request<FirebaseProject> {
        Request(path: path, method: "GET", id: "projects_get")
    }

    /// Search all apps (Android, iOS, Web) in this project.
    ///
    /// `GET v1beta1/projects/{projectId}:searchApps`
    ///
    /// - Parameters:
    ///   - pageSize: Maximum number of apps to return.
    ///   - pageToken: Pagination token from a previous response.
    ///   - filter: Optional filter (e.g. `platform=IOS`).
    /// - Returns: A request that resolves to `SearchFirebaseAppsResponse`.
    public func searchApps(
        pageSize: Int? = nil,
        pageToken: String? = nil,
        filter: String? = nil
    ) -> Request<SearchFirebaseAppsResponse> {
        var query: [(String, String?)] = []
        if let pageSize { query.append(("pageSize", String(pageSize))) }
        if let pageToken { query.append(("pageToken", pageToken)) }
        if let filter { query.append(("filter", filter)) }

        return Request(
            path: path + ":searchApps",
            method: "GET",
            query: query.isEmpty ? nil : query,
            id: "projects_searchApps"
        )
    }

    /// Access Android apps in this project.
    public var androidApps: PlatformApps<ListAndroidAppsResponse> {
        PlatformApps(path: path + "/androidApps")
    }

    /// Access iOS apps in this project.
    public var iosApps: PlatformApps<ListIosAppsResponse> {
        PlatformApps(path: path + "/iosApps")
    }

    /// Access Web apps in this project.
    public var webApps: PlatformApps<ListWebAppsResponse> {
        PlatformApps(path: path + "/webApps")
    }

    /// Get the Google Analytics property linked to this Firebase project.
    ///
    /// `GET v1beta1/projects/{projectId}/analyticsDetails`
    public func analyticsDetails() -> Request<FirebaseAnalyticsDetailsResponse> {
        Request(path: path + "/analyticsDetails", method: "GET", id: "projects_analyticsDetails")
    }
}

// MARK: - Platform Apps

public struct PlatformApps<Response: Decodable> {
    public let path: String

    /// List apps for this platform.
    public func get(
        pageSize: Int? = nil,
        pageToken: String? = nil
    ) -> Request<Response> {
        var query: [(String, String?)] = []
        if let pageSize { query.append(("pageSize", String(pageSize))) }
        if let pageToken { query.append(("pageToken", pageToken)) }

        return Request(
            path: path,
            method: "GET",
            query: query.isEmpty ? nil : query,
            id: "platformApps_list"
        )
    }

    /// Create a new app.
    public func post<Body: Encodable>(_ body: Body) -> Request<OperationResponse> {
        Request(
            path: path,
            method: "POST",
            body: body,
            id: "platformApps_create"
        )
    }

    /// Access a specific app by appId.
    public func id(_ appId: String) -> PlatformAppWithID {
        PlatformAppWithID(path: path + "/\(appId)")
    }
}

// MARK: - Single Platform App

public struct PlatformAppWithID {
    public let path: String

    /// Get the app config file.
    ///
    /// `GET v1beta1/projects/{projectId}/{platform}Apps/{appId}/config`
    public func config() -> Request<AppConfigResponse> {
        Request(path: path + "/config", method: "GET", id: "platformApp_config")
    }

    /// Update (patch) the app.
    ///
    /// `PATCH v1beta1/projects/{projectId}/{platform}Apps/{appId}`
    public func patch<Body: Encodable>(_ body: Body, updateMask: String) -> Request<PatchAppResponse> {
        Request(
            path: path,
            method: "PATCH",
            query: [("updateMask", updateMask)],
            body: body,
            id: "platformApp_patch"
        )
    }

    /// Remove (soft-delete) the app.
    ///
    /// `POST v1beta1/projects/{projectId}/{platform}Apps/{appId}:remove`
    public func remove(immediate: Bool = false) -> Request<OperationResponse> {
        Request(
            path: path + ":remove",
            method: "POST",
            body: RemoveAppRequest(immediate: immediate),
            id: "platformApp_remove"
        )
    }
}

// MARK: - Request/Response Bodies

public struct RemoveAppRequest: Encodable {
    public let immediate: Bool
}

public struct AppConfigResponse: Decodable {
    public let configFilename: String?
    public let configFileContents: String?

    // Web config fields (returned directly, not base64)
    public let projectId: String?
    public let appId: String?
    public let apiKey: String?
    public let authDomain: String?
    public let databaseURL: String?
    public let storageBucket: String?
    public let messagingSenderId: String?
    public let measurementId: String?
}

public struct PatchAppResponse: Decodable {
    public let name: String?
    public let appId: String?
    public let displayName: String?
}

public struct OperationResponse: Decodable {
    public let name: String?
    public let done: Bool?
}

public struct CreateIosAppRequest: Encodable {
    public let bundleId: String
    public let displayName: String?
    public let appStoreId: String?

    public init(bundleId: String, displayName: String? = nil, appStoreId: String? = nil) {
        self.bundleId = bundleId
        self.displayName = displayName
        self.appStoreId = appStoreId
    }
}

public struct CreateAndroidAppRequest: Encodable {
    public let packageName: String
    public let displayName: String?

    public init(packageName: String, displayName: String? = nil) {
        self.packageName = packageName
        self.displayName = displayName
    }
}

public struct CreateWebAppRequest: Encodable {
    public let displayName: String?

    public init(displayName: String? = nil) {
        self.displayName = displayName
    }
}

public struct PatchDisplayNameRequest: Encodable {
    public let displayName: String

    public init(displayName: String) {
        self.displayName = displayName
    }
}
