import BackgroundTasks
import UIKit
import UserNotifications
#if DEBUG
import netfox
#endif

class AppDelegate: NSObject, UIApplicationDelegate {

    private static let refreshTaskIdentifier = "zeroSixteen.stackconnect.refresh"

    /// Minimum interval the OS will respect before launching the next refresh.
    /// iOS may launch later (or never), depending on usage patterns.
    private static let refreshEarliestInterval: TimeInterval = 30 * 60 // 30 minutes

    /// Versioned flag guarding the one-time purge of analytics CSVs left behind by
    /// the pre-per-app (category-rooted) storage layout. Bump the `.vN` suffix if a
    /// future migration needs the cleanup to run again.
    private static let didPurgeLegacyAnalyticsFilesKey = "analytics.didPurgeLegacyUnscopedFiles.v1"

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        #if DEBUG
        NFX.sharedInstance().start()
        Log.print.info("[App] netfox started")
        #endif

        UNUserNotificationCenter.current().delegate = self
        // Ask for notification permission on first launch so background sync can
        // surface status changes and new reviews as local "fake push" alerts.
        Task { await LocalNotificationService.requestAuthorizationIfNeeded() }

        // One-time cleanup of analytics CSVs orphaned by the pre-per-app storage
        // layout. Runs off the launch path (utility priority) so it never blocks
        // UI, and only once — guarded by a versioned UserDefaults flag.
        if !UserDefaults.standard.bool(forKey: Self.didPurgeLegacyAnalyticsFilesKey) {
            Task.detached(priority: .utility) {
                AnalyticsReportFileStore.purgeLegacyUnscopedFiles()
                UserDefaults.standard.set(true, forKey: Self.didPurgeLegacyAnalyticsFilesKey)
            }
        }

        registerBackgroundRefresh()
        scheduleBackgroundRefresh()
        return true
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        scheduleBackgroundRefresh()
    }

    // MARK: - Background refresh

    private func registerBackgroundRefresh() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.refreshTaskIdentifier,
            using: nil
        ) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            Self.handle(refreshTask: refreshTask)
        }
    }

    private func scheduleBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: Self.refreshTaskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: Self.refreshEarliestInterval)
        do {
            try BGTaskScheduler.shared.submit(request)
            Log.print.notice("[BGTask] Refresh scheduled")
        } catch {
            Log.print.error("[BGTask] Failed to schedule refresh: \(error.localizedDescription)")
        }
    }

    private static func handle(refreshTask: BGAppRefreshTask) {
        Log.print.notice("[BGTask] Refresh launched")

        // Reschedule before doing work so we don't lose the cadence if anything throws.
        Task { @MainActor in
            (UIApplication.shared.delegate as? AppDelegate)?.scheduleBackgroundRefresh()
        }

        let work = Task { @MainActor in
            await SyncService.shared.syncAll(mode: .lightweight).value
        }

        refreshTask.expirationHandler = {
            Log.print.warning("[BGTask] Refresh expired before completion")
            work.cancel()
        }

        Task {
            await work.value
            let success = !work.isCancelled
            Log.print.notice("[BGTask] Refresh finished (success=\(success))")
            refreshTask.setTaskCompleted(success: success)
        }
    }
}

extension AppDelegate: UNUserNotificationCenterDelegate {

    // Present notifications as a banner AND keep them in Notification Center
    // (`.list`) even when the app is in the foreground.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }

    // Route a notification tap into the app via its deep link payload.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if let raw = response.notification.request.content.userInfo["deeplink"] as? String,
           let url = URL(string: raw) {
            Task { @MainActor in DeepLinkRouter.shared.open(url) }
        }
        completionHandler()
    }
}
