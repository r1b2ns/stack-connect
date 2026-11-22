import Combine
import Foundation
import StackProtocols

// MARK: - Protocol

@MainActor
protocol HomeViewModelProtocol: ObservableObject {
    var uiState: HomeUiState { get set }
    func loadDashboard() async
    func triggerSync()
    func refresh() async
    func addWidget(_ kind: HomeWidgetKind)
    func removeWidget(id: UUID)
    func moveWidgets(from source: IndexSet, to destination: Int)
    func availableWidgetKinds() -> [HomeWidgetKind]
    func dismissPendingAgreements(accountId: String)
    /// Looks up the account's Account Holder and publishes `uiState.agreementShare`
    /// with a prefilled request to accept the pending agreements. Always produces a
    /// payload — falling back to a generic message when the Account Holder can't be
    /// determined — so the share sheet opens either way.
    func prepareAgreementShare(accountId: String) async
    /// The user tapped the "support the project" card: tracks it and retires the
    /// card for good. Navigation to the tip jar is the View's job.
    func openTipCard()
    /// The user closed the "support the project" card: tracks it and retires the
    /// card for good.
    func dismissTipCard()
    /// The "sign in again" banner's button: with one expired sign-in, starts
    /// it right away (`signInAgain(_:)`); with several, opens the list.
    func startSignInAgain() async
    /// Signs in again to one expired sign-in (`ExpiredSignIn.id`): the Apple
    /// ID sign-in screens for an Apple ID session, Google's page for a Google
    /// login.
    func signInAgain(_ signInId: String) async
    /// Re-reads the expired sign-ins from the status stores.
    func reloadExpiredSignIns() async
    /// The Apple ID sign-in of `uiState.appleSignInAgainId` finished.
    func appleSignInAgainFinished()
    /// Closes the sign-in-again sheet (list or Apple ID sign-in).
    func closeSignInAgainSheet()
    /// The banner's close button: hides it until the next launch, or until
    /// another account's sign-in expires.
    func dismissSignInAgainBanner()
}

// MARK: - UiState

struct HomeUiState {
    /// The store cards, narrowed to the available stores (Google Play only
    /// while `googlePlayAccounts` is ON). Set by the ViewModel.
    var providers: [ProviderType] = FeatureFlags.shared.availableProviders
    var widgets: [any HomeWidget] = []
    var isLoading = false
    var syncState = SyncState()
    var expiredAccount: AccountModel?
    var showExpiredAlert = false
    var expiringSoonAccount: AccountModel?
    var showExpiringSoonAlert = false
    var pendingAgreementsAccounts: [AccountModel] = []
    /// Accounts whose Account Holder lookup is in flight (drives the share button's
    /// loading/disabled state, per account).
    var preparingAgreementShareAccountIds: Set<String> = []
    /// Non-nil while the "ask the Account Holder" share sheet should be shown.
    /// Cleared by the View when the share sheet is dismissed.
    var agreementShare: AgreementSharePayload?
    /// The one-time "support the project" card (rules in `TipJarPromptService`).
    var showTipCard = false

    // MARK: Sign in again

    /// Every personal sign-in (Apple ID session, Google login) that expired,
    /// with its accounts. Kept even while the banner is dismissed.
    var expiredSignIns: [ExpiredSignIn] = []
    /// The "sign in again" banner is visible.
    var showSignInAgainBanner = false
    /// The sheet shown over the Home, if any.
    var signInAgainSheet: HomeSignInAgainSheet?
    /// In the `.choose` sheet: the Apple ID whose sign-in is pushed.
    var appleSignInAgainId: String?
    /// Sign-ins whose Google page is open (`ExpiredSignIn.id`).
    var workingSignInIds: Set<String> = []
    /// Why the last attempt of a sign-in didn't work, per `ExpiredSignIn.id`.
    var signInAgainFeedback: [String: String] = [:]

    /// The total number of accounts that need a new sign-in.
    var expiredAccountCount: Int { expiredSignIns.reduce(0) { $0 + $1.accounts.count } }
}

/// The sheet the "sign in again" banner opens.
enum HomeSignInAgainSheet: Identifiable, Equatable {
    /// The Apple ID sign-in screens for that Apple ID (one expired sign-in).
    case apple(appleId: String)
    /// The list of expired sign-ins to choose from.
    case choose

    var id: String {
        switch self {
        case .apple(let appleId): return "apple:\(appleId)"
        case .choose: return "choose"
        }
    }
}

/// One-shot request to present the share sheet asking an account's Account Holder
/// to accept its pending App Store Connect agreements.
struct AgreementSharePayload: Identifiable, Equatable {
    /// Unique per tap, so sharing the same account twice still re-presents.
    let id = UUID()
    let accountId: String
    let message: AgreementShareMessage
}

// MARK: - Implementation

@MainActor
final class HomeViewModel: HomeViewModelProtocol {

    /// Resolves the team-members source for an account, or `nil` when it has no
    /// usable credentials. Injected so tests never hit the network or the keychain.
    typealias TeamUsersFetcherFactory = (AccountModel) -> (any TeamUsersFetching)?

    @Published var uiState = HomeUiState()

    private let storage: PersistentStorable
    private let keychain: KeyStorable
    private let preferences: KeyStorable
    private let syncService: SyncService
    private let teamUsersFetcherFactory: TeamUsersFetcherFactory
    private let analytics: AnalyticsTracking
    private let tipCard: TipJarCardPresenting
    private let featureFlags: FeatureFlags
    private let signInExpiry: ExpiredSignInResolving
    private let googleAuth: (any GoogleAuthServicing)?
    private let notificationCenter: NotificationCenter
    private var cancellables = Set<AnyCancellable>()

    /// Preferences key of the dashboard layout (also seeded by the DEBUG fake data mode).
    static let widgetsStorageKey = "home.widget.configurations"

    /// Accounts already warned about upcoming expiration this session (avoids repeat alerts).
    private var warnedAccountIds: Set<String> = []

    /// Pending-agreements banners dismissed this session (re-appear next launch if still flagged).
    private var dismissedAgreementAccountIds: Set<String> = []

    /// Accounts whose expired sign-in was on screen when the user closed the
    /// "sign in again" banner. In memory only, on purpose: this ViewModel
    /// lives for the app run (owned by `AppRootViewFactory`), so the banner
    /// stays closed across tabs and layouts, and is back on the next launch.
    /// An account that expires after the close shows the banner again; one
    /// that recovers is forgotten, so expiring again later shows it too.
    private var dismissedSignInAccountIds: Set<String> = []

    init(
        storage: PersistentStorable? = nil,
        keychain: KeyStorable = KeychainStorable.shared,
        preferences: KeyStorable = UserDefaultsStorable(),
        syncService: SyncService = .shared,
        teamUsersFetcherFactory: TeamUsersFetcherFactory? = nil,
        analytics: AnalyticsTracking = AnalyticsService.shared,
        tipCard: TipJarCardPresenting = TipJarPromptService.shared,
        featureFlags: FeatureFlags = .shared,
        signInExpiry: ExpiredSignInResolving? = nil,
        googleAuth: (any GoogleAuthServicing)? = nil,
        notificationCenter: NotificationCenter = .default
    ) {
        self.storage = storage ?? SwiftDataStorable.shared
        self.featureFlags = featureFlags
        self.analytics = analytics
        self.tipCard = tipCard
        self.signInExpiry = signInExpiry ?? ExpiredSignInResolver(keychain: keychain)
        self.googleAuth = googleAuth
        self.notificationCenter = notificationCenter
        self.keychain = keychain
        self.preferences = preferences
        self.syncService = syncService
        // Default: the account's real App Store Connect connection, built from its
        // keychain credentials (same path as `UserAccessViewModel`).
        self.teamUsersFetcherFactory = teamUsersFetcherFactory ?? { [keychain] account in
            guard let credentials: AppleCredentials = keychain.object(forKey: "credentials.\(account.id)") else {
                return nil
            }
            return AppleAccountConnection(credentials: credentials)
        }

        uiState.providers = featureFlags.availableProviders
        loadWidgetConfigurations()

        syncService.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newState in
                guard let self else { return }
                let previousTimestamp = self.uiState.syncState.lastSyncedAt
                self.uiState.syncState = newState
                if newState.lastSyncedAt != previousTimestamp {
                    Task { await self.loadDashboard() }
                }
            }
            .store(in: &cancellables)

        tipCard.isCardVisiblePublisher
            .removeDuplicates()
            .sink { [weak self] isVisible in
                guard let self else { return }
                // `tip_card_shown` once each time the card appears.
                if isVisible && !self.uiState.showTipCard {
                    self.analytics.track(.action(.tipCardShown, on: .home))
                }
                self.uiState.showTipCard = isVisible
            }
            .store(in: &cancellables)

        // An Apple ID session or a Google login expired or works again: the
        // banner, and the account status chips of the widget rows.
        notificationCenter.publisher(for: .signInStatusDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                Task {
                    await self?.reloadExpiredSignIns()
                    await self?.reloadWidgets()
                }
            }
            .store(in: &cancellables)
    }

    func triggerSync() {
        syncService.syncAll(trigger: .foreground, screen: .home)
    }

    /// Pull-to-refresh. Tracked as a `refresh` action with the sync outcome.
    func refresh() async {
        await syncService.syncAll(trigger: .manual, screen: .home).value
        await loadDashboard()
        analytics.track(.action(.refresh, on: .home, result: syncService.state.lastError == nil ? .success : .failure))
    }

    func loadDashboard() async {
        uiState.isLoading = true
        defer { uiState.isLoading = false }

        await reloadWidgets()
        await checkExpiredAccounts()
    }

    // MARK: - Account Expiration

    private func checkExpiredAccounts() async {
        let accounts = featureFlags.visibleAccounts((try? await storage.fetchAll(AccountModel.self)) ?? [])
        if let expired = accounts.first(where: { $0.isExpired }) {
            uiState.expiredAccount = expired
            uiState.showExpiredAlert = true
        } else if let expiringSoon = accounts.first(where: { $0.isExpiringSoon && !warnedAccountIds.contains($0.id) }) {
            warnedAccountIds.insert(expiringSoon.id)
            uiState.expiringSoonAccount = expiringSoon
            uiState.showExpiringSoonAlert = true
        }

        // Reuse the same fetch — no extra round-trip — to surface pending-agreements banners.
        uiState.pendingAgreementsAccounts = accounts.filter {
            $0.providerType == .apple
                && $0.hasPendingAgreements
                && !dismissedAgreementAccountIds.contains($0.id)
        }
        applyExpiredSignIns(signInExpiry.expiredSignIns(in: accounts))
    }

    // MARK: - Sign In Again

    /// Re-reads the expired sign-ins (a status store changed).
    func reloadExpiredSignIns() async {
        // Accounts of a hidden store (Google Play while `googlePlayAccounts`
        // is OFF) never reach the banner, as in `checkExpiredAccounts()`.
        let accounts = featureFlags.visibleAccounts((try? await storage.fetchAll(AccountModel.self)) ?? [])
        applyExpiredSignIns(signInExpiry.expiredSignIns(in: accounts))
    }

    private func applyExpiredSignIns(_ signIns: [ExpiredSignIn]) {
        uiState.expiredSignIns = signIns
        let ids = Set(signIns.map(\.id))
        uiState.workingSignInIds.formIntersection(ids)
        uiState.signInAgainFeedback = uiState.signInAgainFeedback.filter { ids.contains($0.key) }

        let expiredAccountIds = Set(signIns.flatMap { $0.accounts.map(\.id) })
        // A recovered account forgets the close: expiring again shows the banner.
        dismissedSignInAccountIds.formIntersection(expiredAccountIds)
        uiState.showSignInAgainBanner = !expiredAccountIds.subtracting(dismissedSignInAccountIds).isEmpty

        // Nothing left to choose from: close the list (never the Apple ID
        // sign-in in progress, which closes itself when it finishes).
        if signIns.isEmpty, uiState.signInAgainSheet == .choose, uiState.appleSignInAgainId == nil {
            uiState.signInAgainSheet = nil
        }
    }

    func startSignInAgain() async {
        let signIns = uiState.expiredSignIns
        if signIns.count == 1, let only = signIns.first {
            await signInAgain(only.id)
        } else if !signIns.isEmpty {
            analytics.track(.buttonTap(.chooseSignInAgain, on: .home))
            uiState.appleSignInAgainId = nil
            uiState.signInAgainSheet = .choose
        }
    }

    func signInAgain(_ signInId: String) async {
        guard let signIn = uiState.expiredSignIns.first(where: { $0.id == signInId }),
              !uiState.workingSignInIds.contains(signInId) else { return }
        switch signIn.provider {
        case .appleId(let appleId):
            analytics.track(.buttonTap(.signInAgain, on: .home))
            if uiState.signInAgainSheet == .choose {
                uiState.appleSignInAgainId = appleId
            } else {
                uiState.signInAgainSheet = .apple(appleId: appleId)
            }
        case .google(let loginId):
            await signInToGoogleAgain(signIn, loginId: loginId)
        }
    }

    /// Google's page for the same Google user (`GoogleAccessRecovery`, which
    /// tracks the tap and the outcome). On success `GoogleAuthService` records
    /// the login as working again (`.signInStatusDidChange`); the list is
    /// re-read right away and the accounts sync again.
    private func signInToGoogleAgain(_ signIn: ExpiredSignIn, loginId: String) async {
        let recovery = GoogleAccessRecovery(
            loginId: loginId,
            providerType: signIn.accounts.first?.providerType ?? .googlePlay,
            auth: googleAuth,
            analytics: analytics,
            screen: .home
        )
        let prompt = GoogleAccessPrompt(reason: .signInRequired, email: signIn.login)
        let resolved = await recovery.resolve(prompt) { update in
            if update.isWorking {
                self.uiState.workingSignInIds.insert(signIn.id)
            } else {
                self.uiState.workingSignInIds.remove(signIn.id)
            }
            self.uiState.signInAgainFeedback[signIn.id] = update.feedback
        }
        uiState.workingSignInIds.remove(signIn.id)
        guard resolved else { return }
        uiState.signInAgainFeedback[signIn.id] = nil
        await reloadExpiredSignIns()
        triggerSync()
    }

    func appleSignInAgainFinished() {
        // `AppleIdSignInViewModel` already cleared the session's expiry.
        if uiState.signInAgainSheet == .choose, uiState.expiredSignIns.count > 1 {
            uiState.appleSignInAgainId = nil
        } else {
            uiState.signInAgainSheet = nil
            uiState.appleSignInAgainId = nil
        }
        Task {
            await reloadExpiredSignIns()
            triggerSync()
        }
    }

    func closeSignInAgainSheet() {
        uiState.signInAgainSheet = nil
        uiState.appleSignInAgainId = nil
    }

    func dismissSignInAgainBanner() {
        analytics.track(.buttonTap(.dismissSignInAgainBanner, on: .home))
        dismissedSignInAccountIds.formUnion(uiState.expiredSignIns.flatMap { $0.accounts.map(\.id) })
        uiState.showSignInAgainBanner = false
    }

    // MARK: - Pending Agreements

    func dismissPendingAgreements(accountId: String) {
        analytics.track(.buttonTap(.dismissAgreementsBanner, on: .home))
        dismissedAgreementAccountIds.insert(accountId)
        uiState.pendingAgreementsAccounts.removeAll { $0.id == accountId }
    }

    func prepareAgreementShare(accountId: String) async {
        analytics.track(.buttonTap(.shareAgreementsRequest, on: .home))
        // Ignore re-taps while this account's lookup is still running.
        guard !uiState.preparingAgreementShareAccountIds.contains(accountId),
              let account = uiState.pendingAgreementsAccounts.first(where: { $0.id == accountId }) else { return }

        uiState.preparingAgreementShareAccountIds.insert(accountId)
        defer { uiState.preparingAgreementShareAccountIds.remove(accountId) }

        // Fetched on every tap on purpose (no caching): users aren't persisted and
        // the Account Holder can change.
        let accountHolder = await fetchAccountHolder(for: account)
        uiState.agreementShare = AgreementSharePayload(
            accountId: accountId,
            message: AgreementShareMessage.make(teamName: account.name, accountHolder: accountHolder)
        )
        analytics.track(.action(
            .shareAgreementsRequest,
            on: .home,
            result: .success,
            parameters: [AnalyticsParameterKey.hasAccountHolder: .bool(accountHolder != nil)]
        ))
    }

    /// Returns the team member holding the `ACCOUNT_HOLDER` role, or `nil` when it
    /// can't be determined. Failures are logged, never surfaced: Apple may answer
    /// `/v1/users` with 403 `PLA_NOT_ACCEPTED` while agreements are pending, or the
    /// API key may lack permission to list users — the caller then shares the
    /// generic message instead.
    private func fetchAccountHolder(for account: AccountModel) async -> UserModel? {
        guard let fetcher = teamUsersFetcherFactory(account) else {
            Log.print.error("[Home] No credentials for account \(account.id); sharing the generic agreements request")
            return nil
        }
        do {
            let users = try await fetcher.fetchUsers()
            guard let accountHolder = users.first(where: { $0.roles.contains(UserRoleCatalog.accountHolder) }) else {
                Log.print.info("[Home] No Account Holder among \(users.count) users of account \(account.id); sharing the generic agreements request")
                return nil
            }
            return accountHolder
        } catch {
            Log.print.error("[Home] Account Holder lookup failed for account \(account.id): \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Tip Card

    func openTipCard() {
        analytics.track(.buttonTap(.openTipCard, on: .home))
        retireTipCard()
    }

    func dismissTipCard() {
        analytics.track(.buttonTap(.dismissTipCard, on: .home))
        retireTipCard()
    }

    private func retireTipCard() {
        uiState.showTipCard = false
        tipCard.retireCard()
    }

    // MARK: - Widgets

    func addWidget(_ kind: HomeWidgetKind) {
        guard !uiState.widgets.contains(where: { $0.kind == kind }) else { return }
        analytics.track(.action(.addWidget, on: .customizeWidgets, parameters: [AnalyticsParameterKey.kind: .string(kind.rawValue)]))
        let config = HomeWidgetConfiguration(kind: kind)
        let widget = HomeWidgetRegistry.make(for: config, storage: storage, featureFlags: featureFlags)
        uiState.widgets.append(widget)
        saveWidgetConfigurations()
        Task { await widget.load() }
    }

    func removeWidget(id: UUID) {
        if let kind = uiState.widgets.first(where: { $0.id == id })?.kind {
            analytics.track(.action(.removeWidget, on: .customizeWidgets, parameters: [AnalyticsParameterKey.kind: .string(kind.rawValue)]))
        }
        uiState.widgets.removeAll { $0.id == id }
        saveWidgetConfigurations()
    }

    func moveWidgets(from source: IndexSet, to destination: Int) {
        analytics.track(.action(.reorderWidgets, on: .customizeWidgets))
        uiState.widgets.move(fromOffsets: source, toOffset: destination)
        saveWidgetConfigurations()
    }

    func availableWidgetKinds() -> [HomeWidgetKind] {
        let active = Set(uiState.widgets.map { $0.kind })
        return HomeWidgetKind.allCases.filter { !active.contains($0) }
    }

    private func loadWidgetConfigurations() {
        let configurations: [HomeWidgetConfiguration] = preferences.object(forKey: Self.widgetsStorageKey)
            ?? HomeWidgetRegistry.defaultConfigurations
        uiState.widgets = configurations.map { config in
            HomeWidgetRegistry.make(for: config, storage: storage, featureFlags: featureFlags)
        }
    }

    private func saveWidgetConfigurations() {
        let configurations = uiState.widgets.map { $0.configuration }
        preferences.setObject(configurations, forKey: Self.widgetsStorageKey)
    }

    private func reloadWidgets() async {
        for widget in uiState.widgets {
            await widget.load()
        }
    }
}
