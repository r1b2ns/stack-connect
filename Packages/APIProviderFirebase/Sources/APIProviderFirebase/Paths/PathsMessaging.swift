import Foundation

private let fcmBaseURL = URL(string: "https://fcm.googleapis.com")!
private let fcmDataBaseURL = URL(string: "https://fcmdata.googleapis.com")!

// MARK: - FCM Messaging

/// Access the FCM HTTP v1 API for sending messages.
public struct FCMMessaging {
    public let path: String

    /// Send a message to a target (token, topic, or condition).
    ///
    /// `POST https://fcm.googleapis.com/v1/projects/{projectId}/messages:send`
    public func send(_ body: FCMSendRequest) -> Request<FCMSendResponse> {
        Request(
            path: path + ":send",
            method: "POST",
            body: body,
            id: "fcm_messages_send",
            customBaseURL: fcmBaseURL
        )
    }
}

// MARK: - FCM Data API (Delivery Stats)

/// Access the FCM Data API for delivery statistics (Android only, beta).
public struct FCMDeliveryData {
    public let path: String

    /// List delivery data for an Android app.
    ///
    /// `GET https://fcmdata.googleapis.com/v1beta1/projects/{projectId}/androidApps/{appId}/deliveryData`
    public func list(
        pageSize: Int? = nil,
        pageToken: String? = nil
    ) -> Request<FCMDeliveryDataResponse> {
        var query: [(String, String?)] = []
        if let pageSize { query.append(("pageSize", String(pageSize))) }
        if let pageToken { query.append(("pageToken", pageToken)) }

        return Request(
            path: path,
            method: "GET",
            query: query.isEmpty ? nil : query,
            id: "fcm_deliveryData_list",
            customBaseURL: fcmDataBaseURL
        )
    }
}
