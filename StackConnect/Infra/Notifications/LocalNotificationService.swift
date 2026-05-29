import Foundation
import UserNotifications

/// Schedules the app's "fake push" local notifications. The app has no push
/// server, so background sync surfaces app status changes and new user reviews
/// as local notifications instead.
enum LocalNotificationService {

    /// Max lines listed in a grouped notification body before collapsing the rest.
    private static let maxLines = 5

    // MARK: - Permission

    /// Requests notification permission the first time only (no-op afterwards).
    static func requestAuthorizationIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else { return }
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    // MARK: - Scheduling

    /// One grouped notification for all app status changes in this sync.
    static func scheduleStatusChanges(_ changes: [SyncChange.StatusChange]) async {
        guard !changes.isEmpty, await isAuthorized() else { return }

        let title: String
        let body: String
        let link: DeepLink

        if changes.count == 1, let change = changes.first {
            title = change.appName
            body = change.newState.displayName
            link = .app(accountId: change.accountId, appId: change.appId)
        } else {
            title = String(localized: "\(changes.count) apps changed status")
            body = collapsedBody(changes.map { "\($0.appName) — \($0.newState.displayName)" })
            link = .home
        }

        await post(title: title, body: body, deepLink: link, category: "status")
    }

    /// One grouped notification for all newly received reviews in this sync.
    static func scheduleNewReviews(_ reviews: [SyncChange.NewReview]) async {
        guard !reviews.isEmpty, await isAuthorized() else { return }

        let title: String
        let body: String
        let link: DeepLink

        if reviews.count == 1, let review = reviews.first {
            title = review.appName
            body = String(localized: "Received a new review")
            link = .review(accountId: review.accountId, appId: review.appId, reviewId: review.reviewId)
        } else {
            title = String(localized: "New reviews")
            // Group by app, preserving first-seen order.
            var order: [String] = []
            var byApp: [String: (name: String, count: Int)] = [:]
            for review in reviews {
                if byApp[review.appId] == nil {
                    order.append(review.appId)
                    byApp[review.appId] = (review.appName, 0)
                }
                byApp[review.appId]?.count += 1
            }
            let lines = order.compactMap { appId -> String? in
                guard let entry = byApp[appId] else { return nil }
                return String(localized: "\(entry.name) — \(entry.count) new reviews")
            }
            body = collapsedBody(lines)
            link = .home
        }

        await post(title: title, body: body, deepLink: link, category: "reviews")
    }

    // MARK: - Helpers

    private static func collapsedBody(_ lines: [String]) -> String {
        guard lines.count > maxLines else { return lines.joined(separator: "\n") }
        let shown = lines.prefix(maxLines).joined(separator: "\n")
        let remaining = lines.count - maxLines
        return shown + "\n" + String(localized: "and \(remaining) more")
    }

    private static func isAuthorized() async -> Bool {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        default:
            return false
        }
    }

    private static func post(title: String, body: String, deepLink: DeepLink, category: String) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = ["deeplink": deepLink.url.absoluteString]

        let request = UNNotificationRequest(
            identifier: "\(category).\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        try? await UNUserNotificationCenter.current().add(request)
    }
}
