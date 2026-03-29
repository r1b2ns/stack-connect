import UIKit
#if DEBUG
import netfox
#endif

class AppDelegate: NSObject, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        #if DEBUG
        NFX.sharedInstance().start()
        Log.print.info("[App] netfox started")
        #endif
        return true
    }
}
