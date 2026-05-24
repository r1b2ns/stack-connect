import SwiftUI
import SwiftData
import TipKit

@main
struct StackConnectApp: App {

    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
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

        try? Tips.configure([
            .displayFrequency(.immediate),
            .datastoreLocation(.applicationDefault)
        ])
    }

    var body: some Scene {
        WindowGroup {
            HomeViewFactory.build()
                .sheet(isPresented: $showWelcome) {
                    WelcomeView {
                        UserDefaults.standard.set(true, forKey: "hasSeenWelcome")
                        showWelcome = false
                    }
                    .interactiveDismissDisabled(true)
                }
                .modelContainer(modelContainer)
        }
    }
}
