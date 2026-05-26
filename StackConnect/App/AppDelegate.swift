import BackgroundTasks
import UIKit
#if DEBUG
import netfox
#endif

class AppDelegate: NSObject, UIApplicationDelegate {

    private static let refreshTaskIdentifier = "zeroSixteen.stackconnect.refresh"

    /// Minimum interval the OS will respect before launching the next refresh.
    /// iOS may launch later (or never), depending on usage patterns.
    private static let refreshEarliestInterval: TimeInterval = 30 * 60 // 30 minutes

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        #if DEBUG
        NFX.sharedInstance().start()
        Log.print.info("[App] netfox started")
        #endif

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
            Log.print.info("[BGTask] Refresh scheduled")
        } catch {
            Log.print.error("[BGTask] Failed to schedule refresh: \(error.localizedDescription)")
        }
    }

    private static func handle(refreshTask: BGAppRefreshTask) {
        Log.print.info("[BGTask] Refresh launched")

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
            Log.print.info("[BGTask] Refresh finished (success=\(success))")
            refreshTask.setTaskCompleted(success: success)
        }
    }
}
