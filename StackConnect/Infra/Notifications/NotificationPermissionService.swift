import Combine
import StackProtocols
import UIKit
import UserNotifications

/// The system notification authorization the app reads and asks for. A seam
/// so the permission flow and its analytics are unit tested without the
/// real prompt.
protocol NotificationAuthorizationCenter: Sendable {
    func authorizationStatus() async -> UNAuthorizationStatus
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool
}

/// `UNUserNotificationCenter.current()`.
struct SystemNotificationAuthorizationCenter: NotificationAuthorizationCenter {
    func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        try await UNUserNotificationCenter.current().requestAuthorization(options: options)
    }
}

/// Asks for notification permission. Split out so `SyncService` depends on
/// the one call it needs.
@MainActor
protocol NotificationPermissionRequesting: AnyObject {
    /// Shows the system prompt when the user hasn't answered it yet; returns
    /// whether notifications are allowed (now or already).
    @discardableResult
    func requestAuthorization(options: UNAuthorizationOptions) async -> Bool
}

/// The one place that shows the notification permission prompt and reports
/// it: the answer as a `request_notification_permission` action (`success` =
/// granted, `cancelled` = denied, `failure` = the request threw), and the
/// `notifications_enabled` user property, refreshed after the prompt, at
/// launch and whenever the app becomes active.
@MainActor
final class NotificationPermissionService: NotificationPermissionRequesting {

    static let shared = NotificationPermissionService()

    private let center: NotificationAuthorizationCenter
    private let analytics: AnalyticsTracking
    private let userProperties: AnalyticsUserPropertySetting
    private let notificationCenter: NotificationCenter
    private var subscription: AnyCancellable?

    init(
        center: NotificationAuthorizationCenter = SystemNotificationAuthorizationCenter(),
        analytics: AnalyticsTracking = AnalyticsService.shared,
        userProperties: AnalyticsUserPropertySetting = AnalyticsService.shared,
        notificationCenter: NotificationCenter = .default
    ) {
        self.center = center
        self.analytics = analytics
        self.userProperties = userProperties
        self.notificationCenter = notificationCenter
    }

    @discardableResult
    func requestAuthorization(options: UNAuthorizationOptions) async -> Bool {
        let status = await center.authorizationStatus()
        guard status == .notDetermined else {
            setUserProperty(enabled: Self.isEnabled(status))
            return Self.isEnabled(status)
        }

        let granted: Bool
        do {
            granted = try await center.requestAuthorization(options: options)
            analytics.track(.action(
                .requestNotificationPermission,
                on: nil,
                result: granted ? .success : .cancelled,
                parameters: [AnalyticsParameterKey.enabled: .bool(granted)]
            ))
        } catch {
            Log.print.error("[Notifications] Permission request failed: \(error.localizedDescription)")
            granted = false
            analytics.track(.action(.requestNotificationPermission, on: nil, result: .failure))
        }
        setUserProperty(enabled: granted)
        return granted
    }

    /// Reads the current setting into `notifications_enabled`.
    func refreshUserProperty() async {
        setUserProperty(enabled: Self.isEnabled(await center.authorizationStatus()))
    }

    /// Refreshes `notifications_enabled` now and every time the app becomes
    /// active. Calling it again is a no-op for the observation.
    func startObserving() {
        if subscription == nil {
            subscription = notificationCenter.publisher(for: UIApplication.didBecomeActiveNotification)
                .sink { [weak self] _ in
                    Task { @MainActor [weak self] in await self?.refreshUserProperty() }
                }
        }
        Task { await refreshUserProperty() }
    }

    /// Provisional and ephemeral authorizations deliver notifications too.
    nonisolated static func isEnabled(_ status: UNAuthorizationStatus) -> Bool {
        switch status {
        case .authorized, .provisional, .ephemeral: return true
        case .denied, .notDetermined: return false
        @unknown default: return false
        }
    }

    // MARK: - Private

    private func setUserProperty(enabled: Bool) {
        userProperties.setUserProperties([.notificationsEnabled: String(enabled)])
    }
}
