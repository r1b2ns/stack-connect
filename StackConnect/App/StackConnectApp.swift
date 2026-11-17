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
        // The core's diagnostic log sink goes in before anything can `connect`
        // (fake data mode included: the fakes just never produce core lines).
        CoreLoggerInstaller.shared.install()

        // Analytics first, before the app delegate and any view: builds
        // `AnalyticsService.shared` (configuring Firebase only when
        // GoogleService-Info.plist is bundled) and applies the user's opt-out
        // setting to the SDK before anything can be tracked.
        AnalyticsService.shared.applyCollectionSetting()

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
            let container = try Self.makeModelContainer()
            self.modelContainer = container
            SwiftDataStorable.shared = SwiftDataStorable.make(modelContainer: container)
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }

        try? Tips.configure([
            .displayFrequency(.immediate),
            .datastoreLocation(.applicationDefault)
        ])

        #if DEBUG
        // Demo / screenshot sessions start straight on the dashboard: no
        // welcome, release notes or tips over the fake data.
        if FakeDataMode.current.isEnabled {
            _showWelcome = State(initialValue: false)
            _showReleaseNotes = State(initialValue: false)
            Tips.hideAllTipsForTesting()
        }
        #endif
    }

    /// The App Group store shared with the widget extension, or — in the DEBUG
    /// fake data mode — a private store with demo accounts, after every backend
    /// seam has been swapped for its fake (`FakeDataBootstrap`).
    @MainActor
    private static func makeModelContainer() throws -> ModelContainer {
        #if DEBUG
        if FakeDataMode.current.isEnabled {
            return try FakeDataBootstrap.install(mode: .current)
        }
        #endif
        let configuration = ModelConfiguration(
            groupContainer: .identifier(AppGroup.identifier)
        )
        return try ModelContainer(for: PersistedItem.self, configurations: configuration)
    }

    /// The app is the host of a unit-test run: it shows no UI, so the Home
    /// never starts a sync against the simulator's real accounts (network and
    /// Google Play quota) while tests run.
    private static let isUnitTestHost = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

    var body: some Scene {
        WindowGroup {
            if Self.isUnitTestHost {
                Color.clear
            } else {
                buildRoot()
            }
        }
    }

    @ViewBuilder
    private func buildRoot() -> some View {
        HomeViewFactory.build()
            .offlineBanner()
            // App Store review request after a successful foreground sync,
            // every third launch, at most once per launch.
            .reviewPromptOnSuccessfulSync()
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
