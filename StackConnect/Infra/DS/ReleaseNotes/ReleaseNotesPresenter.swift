import Foundation

/// Decides whether the ``ReleaseNotesView`` should be presented.
///
/// Release notes are shown once per installed version: the first time the app
/// runs after a fresh install or after an update, the notes for the current
/// version are displayed. Once acknowledged, they stay hidden until the app is
/// updated to a newer version.
struct ReleaseNotesPresenter {

    private static let lastSeenVersionKey = "lastSeenReleaseNotesVersion"

    private let defaults: UserDefaults
    private let currentVersion: String

    init(
        defaults: UserDefaults = .standard,
        currentVersion: String = ReleaseNotesPresenter.appVersion
    ) {
        self.defaults = defaults
        self.currentVersion = currentVersion
    }

    /// The app marketing version (`CFBundleShortVersionString`).
    static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    /// `true` when the release notes for the current version have not been seen yet.
    var shouldPresent: Bool {
        defaults.string(forKey: Self.lastSeenVersionKey) != currentVersion
    }

    /// Marks the current version's release notes as seen so they won't show again
    /// until the next update.
    func markAsSeen() {
        defaults.set(currentVersion, forKey: Self.lastSeenVersionKey)
    }
}
