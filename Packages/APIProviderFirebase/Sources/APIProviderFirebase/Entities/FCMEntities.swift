import Foundation

// MARK: - Send Message

/// Request body for `POST /v1/projects/{projectId}/messages:send`
public struct FCMSendRequest: Encodable {
    public let message: FCMMessage

    public init(message: FCMMessage) {
        self.message = message
    }
}

/// A single FCM message.
public struct FCMMessage: Encodable {
    /// Target – exactly one of: token, topic, condition.
    public var token: String?
    public var topic: String?
    public var condition: String?

    public var notification: FCMNotification?
    public var data: [String: String]?
    public var android: FCMAndroidConfig?
    public var apns: FCMApnsConfig?
    public var fcmOptions: FCMOptions?

    public init(
        token: String? = nil,
        topic: String? = nil,
        condition: String? = nil,
        notification: FCMNotification? = nil,
        data: [String: String]? = nil,
        android: FCMAndroidConfig? = nil,
        apns: FCMApnsConfig? = nil,
        fcmOptions: FCMOptions? = nil
    ) {
        self.token = token
        self.topic = topic
        self.condition = condition
        self.notification = notification
        self.data = data
        self.android = android
        self.apns = apns
        self.fcmOptions = fcmOptions
    }

    enum CodingKeys: String, CodingKey {
        case token, topic, condition, notification, data, android, apns
        case fcmOptions = "fcm_options"
    }
}

public struct FCMNotification: Encodable {
    public var title: String?
    public var body: String?
    public var image: String?

    public init(title: String? = nil, body: String? = nil, image: String? = nil) {
        self.title = title
        self.body = body
        self.image = image
    }
}

public struct FCMAndroidConfig: Encodable {
    public var priority: String?
    public var notification: FCMAndroidNotification?

    public init(priority: String? = nil, notification: FCMAndroidNotification? = nil) {
        self.priority = priority
        self.notification = notification
    }

    public struct FCMAndroidNotification: Encodable {
        public var channelId: String?
        public var sound: String?

        public init(channelId: String? = nil, sound: String? = nil) {
            self.channelId = channelId
            self.sound = sound
        }

        enum CodingKeys: String, CodingKey {
            case channelId = "channel_id"
            case sound
        }
    }
}

public struct FCMApnsConfig: Encodable {
    public var payload: FCMApnsPayload?

    public init(payload: FCMApnsPayload? = nil) {
        self.payload = payload
    }

    public struct FCMApnsPayload: Encodable {
        public var aps: FCMAps?

        public init(aps: FCMAps? = nil) { self.aps = aps }

        public struct FCMAps: Encodable {
            public var sound: String?
            public var badge: Int?

            public init(sound: String? = nil, badge: Int? = nil) {
                self.sound = sound
                self.badge = badge
            }
        }
    }
}

public struct FCMOptions: Encodable {
    public var analyticsLabel: String?

    public init(analyticsLabel: String? = nil) {
        self.analyticsLabel = analyticsLabel
    }

    enum CodingKeys: String, CodingKey {
        case analyticsLabel = "analytics_label"
    }
}

/// Response from a successful send.
public struct FCMSendResponse: Decodable {
    /// The message resource name: `projects/{project_id}/messages/{message_id}`
    public let name: String?
}

// MARK: - FCM Data API (delivery stats)

/// Response from `GET fcmdata.googleapis.com/v1beta1/projects/{projectId}/androidApps/{appId}/deliveryData`
public struct FCMDeliveryDataResponse: Decodable {
    public let androidDeliveryData: [AndroidDeliveryData]?
    public let nextPageToken: String?
}

public struct AndroidDeliveryData: Decodable, Identifiable {
    public let appId: String?
    public let date: DateInfo?
    public let data: DeliveryDataMetrics?
    public let analyticsLabel: String?

    public var id: String {
        "\(appId ?? "")-\(date?.year ?? 0)-\(date?.month ?? 0)-\(date?.day ?? 0)-\(analyticsLabel ?? "")"
    }

    public struct DateInfo: Decodable {
        public let year: Int?
        public let month: Int?
        public let day: Int?

        public var formatted: String {
            guard let y = year, let m = month, let d = day else { return "–" }
            return String(format: "%04d-%02d-%02d", y, m, d)
        }
    }

    public struct DeliveryDataMetrics: Decodable {
        public let countMessagesAccepted: String?
        public let messageOutcomePercents: MessageOutcomePercents?
        public let deliveryPerformancePercents: DeliveryPerformancePercents?
    }

    public struct MessageOutcomePercents: Decodable {
        public let delivered: Float?
        public let pending: Float?
        public let droppedTooManyPendingMessages: Float?
        public let droppedDeviceInactive: Float?
        public let droppedAppForceStopped: Float?
        public let collapsed: Float?
    }

    public struct DeliveryPerformancePercents: Decodable {
        public let deliveredNoDelay: Float?
        public let delayedDeviceDoze: Float?
        public let delayedDeviceOffline: Float?
        public let delayedMessageThrottled: Float?
    }
}
