import Foundation

// MARK: - Search Apps Response

/// Response from `GET v1beta1/projects/{projectId}:searchApps`.
public struct SearchFirebaseAppsResponse: Decodable {
    public let apps: [FirebaseAppInfo]?
    public let nextPageToken: String?
}

// MARK: - Firebase App Info (unified, lightweight)

/// A unified app representation returned by `searchApps`.
public struct FirebaseAppInfo: Decodable, Identifiable {
    public let name: String?
    public let appId: String?
    public let displayName: String?
    public let platform: Platform?

    public var id: String {
        appId ?? name ?? UUID().uuidString
    }

    public enum Platform: String, Decodable {
        case platformUnspecified = "PLATFORM_UNSPECIFIED"
        case ios = "IOS"
        case android = "ANDROID"
        case web = "WEB"
    }
}

// MARK: - Android Apps

/// Response from `GET v1beta1/projects/{projectId}/androidApps`.
public struct ListAndroidAppsResponse: Decodable {
    public let apps: [AndroidApp]?
    public let nextPageToken: String?
}

public struct AndroidApp: Decodable, Identifiable {
    public let name: String?
    public let appId: String?
    public let displayName: String?
    public let projectId: String?
    public let packageName: String?
    public let apiKeyId: String?
    public let state: AppState?
    public let sha1Hashes: [String]?
    public let sha256Hashes: [String]?
    public let etag: String?

    public var id: String {
        appId ?? name ?? UUID().uuidString
    }
}

// MARK: - iOS Apps

/// Response from `GET v1beta1/projects/{projectId}/iosApps`.
public struct ListIosAppsResponse: Decodable {
    public let apps: [IosApp]?
    public let nextPageToken: String?
}

public struct IosApp: Decodable, Identifiable {
    public let name: String?
    public let appId: String?
    public let displayName: String?
    public let projectId: String?
    public let bundleId: String?
    public let teamId: String?
    public let appStoreId: String?
    public let apiKeyId: String?
    public let state: AppState?
    public let etag: String?

    public var id: String {
        appId ?? name ?? UUID().uuidString
    }
}

// MARK: - Web Apps

/// Response from `GET v1beta1/projects/{projectId}/webApps`.
public struct ListWebAppsResponse: Decodable {
    public let apps: [WebApp]?
    public let nextPageToken: String?
}

public struct WebApp: Decodable, Identifiable {
    public let name: String?
    public let appId: String?
    public let displayName: String?
    public let projectId: String?
    public let appUrls: [String]?
    public let apiKeyId: String?
    public let state: AppState?
    public let etag: String?

    public var id: String {
        appId ?? name ?? UUID().uuidString
    }
}

// MARK: - Shared

public enum AppState: String, Decodable {
    case stateUnspecified = "STATE_UNSPECIFIED"
    case active = "ACTIVE"
    case deleted = "DELETED"
}
