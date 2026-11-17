import Combine
import Foundation

// MARK: - Seams

/// What the Home needs from the "support the project" card: whether it shows,
/// and a way to retire it once the user acts on it.
@MainActor
protocol TipJarCardPresenting: AnyObject {
    /// Emits the current visibility, then every change.
    var isCardVisiblePublisher: AnyPublisher<Bool, Never> { get }
    /// The user tapped the card or closed it: hide it now and never show it
    /// again (persisted).
    func retireCard()
}

/// Records that the user completed a tip, which turns the card off for good.
@MainActor
protocol TipJarTipRecording: AnyObject {
    func recordCompletedTip()
}

// MARK: - Service

/// Decides when to show the one-time "support the project" card on Home.
///
/// The card becomes visible right after a successful foreground sync when all
/// of these hold:
/// 1. The launch count (kept by `ReviewPromptService`, never counted twice) is
///    at least `minimumLaunchCount`.
/// 2. The sync that just ended is a successful foreground one
///    (`ReviewPromptService.isSuccessfulForegroundSyncCompletion`).
/// 3. No App Store review was requested in this launch (the two never stack).
/// 4. The card was never dismissed nor tapped before (persisted).
/// 5. The user never completed a tip (persisted).
/// 6. The process is not a unit-test host nor a DEBUG fake data session.
///
/// Once visible it stays for the rest of the launch until the user acts. Only
/// dismissing, tapping or tipping persist the "never again" flags: a card the
/// user ignores may show again on a later eligible launch.
///
/// DEBUG only: the `-TipJarCardForce YES` launch argument shows the card from
/// the start of the launch and ignores rules 1–6 (it works in fake data mode
/// too), so it can be checked in the simulator. Acting on it still hides it
/// for the rest of the launch.
@MainActor
final class TipJarPromptService: ObservableObject, TipJarCardPresenting, TipJarTipRecording {

    /// `UserDefaults` key: the card was dismissed or tapped.
    nonisolated static let hasRetiredCardKey = "tipJarPrompt.hasRetiredCard"
    /// `UserDefaults` key: the user completed a tip.
    nonisolated static let hasTippedKey = "tipJarPrompt.hasTipped"
    /// DEBUG launch argument (`-TipJarCardForce YES`) forcing the card visible.
    nonisolated static let forceArgumentKey = "TipJarCardForce"

    /// First launch on which the card may show.
    nonisolated static let minimumLaunchCount = 10

    static let shared = TipJarPromptService(
        isEnabled: ReviewPromptService.isEnabledForCurrentProcess,
        isForced: TipJarPromptService.isForcedForCurrentProcess
    )

    @Published private(set) var isCardVisible: Bool

    private let defaults: UserDefaults
    private let isEnabled: Bool
    private let isForced: Bool
    /// Set once the user acted on the card in this launch, so a forced card (or
    /// one whose flag couldn't be persisted) doesn't come back on the next sync.
    private var hasActedThisLaunch = false

    /// - Parameters:
    ///   - defaults: Backing store of the persisted flags. Inject a suite in tests.
    ///   - isEnabled: `false` turns the card off entirely and stops any write
    ///     (unit-test host, DEBUG fake data sessions).
    ///   - isForced: DEBUG override showing the card from the start, ignoring
    ///     every rule.
    init(defaults: UserDefaults = .standard, isEnabled: Bool = true, isForced: Bool = false) {
        self.defaults = defaults
        self.isEnabled = isEnabled
        self.isForced = isForced
        self.isCardVisible = isForced
        if isForced {
            Log.print.info("[TipJarPrompt] Card forced visible by -\(Self.forceArgumentKey)")
        }
    }

    // MARK: - Persisted flags

    /// The card was dismissed or tapped on an earlier (or this) launch.
    var hasRetiredCard: Bool {
        defaults.bool(forKey: Self.hasRetiredCardKey)
    }

    /// The user completed a tip.
    var hasTipped: Bool {
        defaults.bool(forKey: Self.hasTippedKey)
    }

    // MARK: - TipJarCardPresenting

    var isCardVisiblePublisher: AnyPublisher<Bool, Never> {
        $isCardVisible.eraseToAnyPublisher()
    }

    func retireCard() {
        hasActedThisLaunch = true
        isCardVisible = false
        persist(true, forKey: Self.hasRetiredCardKey)
        Log.print.info("[TipJarPrompt] Card retired")
    }

    // MARK: - TipJarTipRecording

    func recordCompletedTip() {
        hasActedThisLaunch = true
        isCardVisible = false
        persist(true, forKey: Self.hasTippedKey)
        Log.print.info("[TipJarPrompt] Tip completed; card turned off")
    }

    // MARK: - Evaluation

    /// Called once a foreground sync ended (see `PostSyncPrompts`), after the
    /// review prompt was decided. Shows the card when every rule holds; never
    /// hides it (only the user's action does).
    func evaluateAfterSync(syncSucceeded: Bool, launchCount: Int, reviewRequestedThisLaunch: Bool) {
        guard !isCardVisible, !hasActedThisLaunch, isEnabled || isForced else { return }

        let shouldShow = Self.shouldShowCard(
            launchCount: launchCount,
            syncSucceeded: syncSucceeded,
            reviewRequestedThisLaunch: reviewRequestedThisLaunch,
            hasRetiredCard: hasRetiredCard,
            hasTipped: hasTipped,
            isForced: isForced
        )
        guard shouldShow else {
            Log.print.info("[TipJarPrompt] Not showing (sync succeeded: \(syncSucceeded), launch #\(launchCount), review this launch: \(reviewRequestedThisLaunch), retired: \(self.hasRetiredCard), tipped: \(self.hasTipped))")
            return
        }
        isCardVisible = true
        Log.print.info("[TipJarPrompt] Showing the card on launch #\(launchCount)")
    }

    // MARK: - Pure rules

    /// The decision itself, free of any state. `isForced` wins over everything.
    nonisolated static func shouldShowCard(
        launchCount: Int,
        syncSucceeded: Bool,
        reviewRequestedThisLaunch: Bool,
        hasRetiredCard: Bool,
        hasTipped: Bool,
        isForced: Bool
    ) -> Bool {
        if isForced { return true }
        return launchCount >= minimumLaunchCount
            && syncSucceeded
            && !reviewRequestedThisLaunch
            && !hasRetiredCard
            && !hasTipped
    }

    // MARK: - Environment

    /// `-TipJarCardForce YES` (also `true` / `1`) in `arguments`. The last
    /// occurrence wins, like the `UserDefaults` argument domain.
    nonisolated static func isForced(arguments: [String]) -> Bool {
        var result = false
        for (index, argument) in arguments.enumerated() where argument == "-\(forceArgumentKey)" {
            let valueIndex = arguments.index(after: index)
            guard valueIndex < arguments.endIndex else { continue }
            result = ["yes", "true", "1"].contains(arguments[valueIndex].lowercased())
        }
        return result
    }

    /// The force argument only exists in DEBUG builds.
    nonisolated static var isForcedForCurrentProcess: Bool {
        #if DEBUG
        return isForced(arguments: ProcessInfo.processInfo.arguments)
        #else
        return false
        #endif
    }

    // MARK: - Private

    /// Writes are skipped while disabled, so a forced card in a fake data
    /// session never touches the real preferences.
    private func persist(_ value: Bool, forKey key: String) {
        guard isEnabled else { return }
        defaults.set(value, forKey: key)
    }
}
