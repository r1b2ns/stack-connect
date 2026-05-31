import SwiftUI
import SwiftData
import TipKit

@main
struct StackConnectApp: App {

    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var showWelcome: Bool
    @State private var showReleaseNotes: Bool
    @State private var releaseNotes: ReleaseNotes?

    private let modelContainer: ModelContainer
    private let releaseNotesPresenter = ReleaseNotesPresenter()

    init() {
        let hasSeenWelcome = UserDefaults.standard.bool(forKey: "hasSeenWelcome")
        let notes = ReleaseNotes.load()
        let presenter = ReleaseNotesPresenter()
        _releaseNotes = State(initialValue: notes)

        // Prefer the release notes: show them on the first launch and on every
        // app update (once per version).
        let canShowReleaseNotes = notes != nil && presenter.shouldPresent
        _showReleaseNotes = State(initialValue: canShowReleaseNotes)

        // The welcome screen is only a fallback, shown when there are no release
        // notes available to display on the first launch.
        _showWelcome = State(initialValue: !hasSeenWelcome && !canShowReleaseNotes)

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
                            // Showing the release notes also completes onboarding,
                            // so the welcome screen won't appear afterwards.
                            UserDefaults.standard.set(true, forKey: "hasSeenWelcome")
                            showReleaseNotes = false
                        }
                        .interactiveDismissDisabled(true)
                    }
                }
                .modelContainer(modelContainer)
        }
    }
}
