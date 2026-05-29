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
            let configuration = ModelConfiguration(
                groupContainer: .identifier(AppGroup.identifier)
            )
            let container = try ModelContainer(for: PersistedItem.self, configurations: configuration)
            self.modelContainer = container
            SwiftDataStorable.shared = SwiftDataStorable.make(modelContainer: container)
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
