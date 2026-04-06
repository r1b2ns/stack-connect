import SwiftUI
import SwiftData

@main
struct StackConnectApp: App {

    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var subscriptionService = SubscriptionService()
    @State private var showWelcome = !UserDefaults.standard.bool(forKey: "hasSeenWelcome")

    private let modelContainer: ModelContainer

    init() {
        do {
            let container = try ModelContainer(for: PersistedItem.self)
            self.modelContainer = container
            SwiftDataStorable.shared = SwiftDataStorable(modelContainer: container)
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if subscriptionService.isSubscribed {
                    HomeViewFactory.build()
                        .sheet(isPresented: $showWelcome) {
                            WelcomeView {
                                UserDefaults.standard.set(true, forKey: "hasSeenWelcome")
                                showWelcome = false
                            }
                            .interactiveDismissDisabled(true)
                        }
                } else {
                    PaywallView()
                }
            }
            .environmentObject(subscriptionService)
            .modelContainer(modelContainer)
            .task {
                await subscriptionService.checkEntitlements()
            }
        }
    }
}
