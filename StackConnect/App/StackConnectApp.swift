import SwiftUI
import SwiftData
import TipKit

@main
struct StackConnectApp: App {

    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var showWelcome = !UserDefaults.standard.bool(forKey: "hasSeenWelcome")
    @State private var showReleaseNotes: Bool
    @State private var releaseNotes: ReleaseNotes?

    private let modelContainer: ModelContainer
    private let releaseNotesPresenter = ReleaseNotesPresenter()

    init() {
        let hasSeenWelcome = UserDefaults.standard.bool(forKey: "hasSeenWelcome")
        let notes = ReleaseNotes.load()
        let presenter = ReleaseNotesPresenter()
        // Only surface release notes after onboarding and once per app version.
        _releaseNotes = State(initialValue: notes)
        _showReleaseNotes = State(
            initialValue: hasSeenWelcome && notes != nil && presenter.shouldPresent
        )

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
                        // On a fresh install the user already sees the welcome
                        // screen, so mark the current version's release notes as
                        // seen to avoid showing them right afterwards.
                        releaseNotesPresenter.markAsSeen()
                        showWelcome = false
                    }
                    .interactiveDismissDisabled(true)
                }
                .sheet(isPresented: $showReleaseNotes) {
                    if let releaseNotes {
                        ReleaseNotesView(releaseNotes: releaseNotes) {
                            releaseNotesPresenter.markAsSeen()
                            showReleaseNotes = false
                        }
                        .interactiveDismissDisabled(true)
                    }
                }
                .modelContainer(modelContainer)
        }
    }
}
