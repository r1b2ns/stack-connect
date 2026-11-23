#if DEBUG
import Foundation
import SwiftData

/// Composition root of the fake data mode (DEBUG only, see `docs/FAKE_DATA.md`).
///
/// Called once from `StackConnectApp.init` when `FakeDataMode.current.isEnabled`,
/// before any screen exists. It swaps every backend seam for its in-memory fake
/// and isolates everything the app persists:
///
/// | Seam | Real | Fake |
/// |---|---|---|
/// | SwiftData | App Group store | `Application Support/FakeData/FakeData.store` |
/// | Keys | Keychain | `FakeKeyStorable` (in memory, seeded each launch) |
/// | Preferences (`UserDefaultsStorable`) | standard defaults | `…fakedata` suite |
/// | App Store Connect / Google Play | Rust core | `FakeCoreProviderFactory` |
/// | Firebase REST APIs | URLSession + OAuth | `FakeFirebaseServer` |
/// | App Store rating summary | iTunes Lookup | `FakeRatingSummaryFetcher` |
/// | Widget icon cache | App Group container | private folder (App Group with `-StackFakeDataWidgets YES`) |
/// | WidgetKit snapshot | App Group container | private folder (App Group with `-StackFakeDataWidgets YES`) |
/// | `URLSession.shared` | network | `FakeNetworkURLProtocol` (fake images, everything else refused) |
enum FakeDataBootstrap {

    static let defaultsSuiteName = "zeroSixteen.stackconnect.fakedata"

    /// Installs the fakes and returns the fake SwiftData container.
    @MainActor
    static func install(mode: FakeDataMode, clock: FakeClock = FakeClock()) throws -> ModelContainer {
        let directory = try baseDirectory()
        if mode.shouldReset {
            reset(directory: directory)
        }

        let container = try makeContainer(directory: directory)
        // No Google Play account unless `googlePlayAccounts` is ON (launch
        // argument): this mode is used to capture App Store screenshots. The
        // flag is deliberately NOT turned on through `sessionDefaults`.
        let includesGooglePlay = FeatureFlags.shared.isEnabled(.googlePlayAccounts)
        try FakeDataSeeder.seedIfNeeded(container: container, clock: clock, includesGooglePlay: includesGooglePlay)
        if let developerId = mode.playDeveloperId {
            try FakeDataSeeder.setPlayDeveloperId(developerId, container: container)
        }

        let keys = FakeKeyStorable()
        FakeDataSeeder.writeCredentials(into: keys)
        KeychainStorable.shared = keys

        if let defaults = UserDefaults(suiteName: defaultsSuiteName) {
            UserDefaultsStorable.sharedDefaults = defaults
            seedDashboardIfNeeded(UserDefaultsStorable(defaults: defaults))
        }

        let playDevelopers = FakeGooglePlayCatalog.makeDevelopers(clock: clock)
        if mode.simulatesPlayQuota {
            // `-StackFakePlayQuota YES`: release summaries hit Google's quota.
            playDevelopers.forEach { $0.state.write { $0.releaseSummariesQuotaExceeded = true } }
        }
        BackendEnvironment.coreProviders = FakeCoreProviderFactory(
            appStoreConnect: FakeAppStoreConnectBackend(clock: clock, teams: FakeAppStoreConnectCatalog.makeTeams(clock: clock)),
            googlePlay: FakeGooglePlayBackend(clock: clock, developers: playDevelopers)
        )
        BackendEnvironment.firebaseProviders = FakeFirebaseProviderFactory(server: FakeFirebaseServer(clock: clock))
        BackendEnvironment.ratingSummaryFetcher = FakeRatingSummaryFetcher()

        // Release writes run against the in-memory Play backend (plan R6).
        FeatureFlags.sessionDefaults[.googlePlayReleaseWrites] = true

        if mode.feedsHomeScreenWidgets {
            // `-StackFakeDataWidgets YES`: the WidgetKit extension can only read
            // the App Group, so the snapshot and the icons go there (they replace
            // the real widget snapshot until the next real sync).
            WidgetIconCache.directoryOverride = nil
            WidgetDashboardSnapshotStore.directoryOverride = nil
        } else {
            WidgetIconCache.directoryOverride = directory.appendingPathComponent("WidgetIcons", isDirectory: true)
            WidgetDashboardSnapshotStore.directoryOverride = directory.appendingPathComponent("Widget", isDirectory: true)
        }
        URLProtocol.registerClass(FakeNetworkURLProtocol.self)

        Log.print.notice("[FakeData] Fake data mode ON (store: \(directory.path, privacy: .public), reset: \(mode.shouldReset), home-screen widgets: \(mode.feedsHomeScreenWidgets), Play quota: \(mode.simulatesPlayQuota))")
        return container
    }

    /// A fresh fake session opens on a full dashboard (every Home widget).
    private static func seedDashboardIfNeeded(_ preferences: KeyStorable) {
        guard preferences.data(forKey: HomeViewModel.widgetsStorageKey) == nil else { return }
        let widgets = HomeWidgetKind.allCases.map { HomeWidgetConfiguration(kind: $0) }
        preferences.setObject(widgets, forKey: HomeViewModel.widgetsStorageKey)
    }

    // MARK: - Store

    static func baseDirectory() throws -> URL {
        let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                  appropriateFor: nil, create: true)
        let directory = support.appendingPathComponent("FakeData", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    static func storeURL(in directory: URL) -> URL {
        directory.appendingPathComponent("FakeData.store")
    }

    static func makeContainer(directory: URL) throws -> ModelContainer {
        let configuration = ModelConfiguration("FakeData", url: storeURL(in: directory))
        return try ModelContainer(for: PersistedItem.self, configurations: configuration)
    }

    /// Deletes the fake store (and its WAL/SHM files), the fake icon cache and
    /// the fake preferences suite, so the next container starts empty.
    static func reset(directory: URL) {
        let fileManager = FileManager.default
        if let contents = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
            for url in contents {
                try? fileManager.removeItem(at: url)
            }
        }
        UserDefaults.standard.removePersistentDomain(forName: defaultsSuiteName)
        Log.print.notice("[FakeData] Fake store reset")
    }
}
#endif
