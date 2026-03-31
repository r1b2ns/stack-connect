import Foundation

/// Root entry point for Firebase Management API endpoints.
///
/// Usage:
/// ```swift
/// let endpoint = FirebaseAPI.v1beta1.projects.get()
/// let response = try await provider.request(endpoint)
///
/// // Remote Config (uses firebaseremoteconfig.googleapis.com)
/// let rcEndpoint = FirebaseAPI.v1.remoteConfig(projectId: "my-project").get()
/// let (template, headers) = try await provider.requestWithHeaders(rcEndpoint)
/// ```
public enum FirebaseAPI {
    public static let v1beta1 = V1Beta1(path: "/v1beta1")
    public static let v1 = V1(path: "/v1")

    /// Access the Google Analytics Data API for a specific property.
    ///
    /// - Parameter propertyId: The numeric GA4 property ID (e.g. "123456789").
    public static func analyticsData(propertyId: String) -> AnalyticsDataProperty {
        AnalyticsDataProperty(path: "/v1beta/properties/\(propertyId)")
    }

    /// Access FCM HTTP v1 API for sending messages.
    ///
    /// - Parameter projectId: The Firebase project ID.
    public static func messaging(projectId: String) -> FCMMessaging {
        FCMMessaging(path: "/v1/projects/\(projectId)/messages")
    }

    /// Access FCM Data API for delivery statistics (Android only).
    ///
    /// - Parameters:
    ///   - projectId: The Firebase project ID.
    ///   - appId: The Android app ID (e.g. "1:123:android:abc").
    public static func deliveryData(projectId: String, appId: String) -> FCMDeliveryData {
        FCMDeliveryData(path: "/v1beta1/projects/\(projectId)/androidApps/\(appId)/deliveryData")
    }
}

// MARK: - V1Beta1

public struct V1Beta1 {
    public let path: String

    public var projects: Projects {
        Projects(path: path + "/projects")
    }
}

// MARK: - V1

public struct V1 {
    public let path: String

    /// Access Remote Config for a specific project.
    public func remoteConfig(projectId: String) -> RemoteConfig {
        RemoteConfig(path: path + "/projects/\(projectId)/remoteConfig")
    }
}

