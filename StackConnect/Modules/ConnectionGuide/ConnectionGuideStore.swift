import Foundation

/// Remembers whether the connection guide was already shown automatically,
/// so it opens on its own before the first account connection only. It
/// stays reachable from Add Account's "How It Works" entry afterwards.
protocol ConnectionGuideStoring {
    /// The guide was shown automatically once (on any provider).
    var hasShownGuide: Bool { get }
    func markGuideShown()
}

/// `ConnectionGuideStoring` in `UserDefaults` (a preference, not a secret).
/// Inject a private suite in tests.
///
/// `@unchecked Sendable`: the only stored property is a `UserDefaults`, which
/// is documented as thread-safe.
struct ConnectionGuideStore: ConnectionGuideStoring, @unchecked Sendable {

    static let hasShownGuideKey = "connectionGuide.hasShownAutomatically"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var hasShownGuide: Bool {
        defaults.bool(forKey: Self.hasShownGuideKey)
    }

    func markGuideShown() {
        guard !hasShownGuide else { return }
        defaults.set(true, forKey: Self.hasShownGuideKey)
        Log.print.info("[ConnectionGuide] Shown automatically: it won't open on its own again")
    }
}
