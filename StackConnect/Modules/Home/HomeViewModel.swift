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
    /// The available stores (Google Play only while `googlePlayAccounts` is
    /// ON). Set by the ViewModel.
    var providers: [ProviderType] = FeatureFlags.shared.availableProviders
    /// The Accounts card (Summary style), which opens the unified accounts list.
    var accountsSummary: AccountsSummary = .empty
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
    /// Apple ID sign-ins (`ExpiredSignIn.id`) whose automatic sign-in waits
    /// for the code Apple sent, with where it went: the banner asks for the
    /// code instead of a new sign-in.
    var awaitingCodeSignIns: [String: AppleSessionCodeDestination] = [:]
    /// The Apple IDs (normalized) an automatic sign-in is renewing right now,
    /// in the order they started: the "Reconnecting Apple ID …" tip, shown for as long as
    /// the attempt runs (apart from the sync line).
    var reconnectingAppleIds: [String] = []
    /// "Apple account reconnected", once an automatic sign-in succeeded.
    var toastMessage: ToastMessage?

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
    private let autoReauth: (any AppleSessionAutoReauthenticating)?
    private let statusResolver: AccountStatusResolving
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
        notificationCenter: NotificationCenter = .default,
        autoReauth: (any AppleSessionAutoReauthenticating)? = nil,
        statusResolver: AccountStatusResolving? = nil
    ) {
        self.autoReauth = autoReauth
        self.storage = storage ?? SwiftDataStorable.shared
        self.featureFlags = featureFlags
        self.analytics = analytics
        self.tipCard = tipCard
        let signInExpiry = signInExpiry ?? ExpiredSignInResolver(keychain: keychain)
        self.signInExpiry = signInExpiry
        self.statusResolver = statusResolver ?? AccountStatusResolver(keychain: keychain, signInExpiry: signInExpiry, autoReauth: autoReauth)
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

        // The Keychain may be readable again (device unlocked, app active): a
        // banner resolved while it couldn't be read is computed again. The
        // widgets refresh their own status chips on the same signal.
        AccountStatusService.keychainMayBeReadable(notificationCenter: notificationCenter)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                Task { await self?.reloadExpiredSignIns() }
            }
            .store(in: &cancellables)

        autoReauth?.events
            .sink { [weak self] event in self?.autoReauthEvent(event) }
            .store(in: &cancellables)

        // The wizard or Settings added, imported or deleted accounts.
        notificationCenter.publisher(for: .accountsDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { await self?.reloadAccountsSummary() }
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

        updateAccountsSummary(with: accounts)

        // Reuse the same fetch — no extra round-trip — to surface pending-agreements banners.
        uiState.pendingAgreementsAccounts = accounts.filter {
            $0.providerType == .apple
                && $0.hasPendingAgreements
                && !dismissedAgreementAccountIds.contains($0.id)
        }
        applyExpiredSignIns(signInExpiry.expiredSignIns(in: accounts))
    }

    // MARK: - Accounts summary

    private func reloadAccountsSummary() async {
        let accounts = featureFlags.visibleAccounts((try? await storage.fetchAll(AccountModel.self)) ?? [])
        updateAccountsSummary(with: accounts)
    }

    private func updateAccountsSummary(with accounts: [AccountModel]) {
        uiState.accountsSummary = AccountsSummary(
            accounts: accounts,
            statuses: statusResolver.statuses(for: accounts),
            providers: featureFlags.availableProviders
        )
    }

    // MARK: - Sign In Again

    /// Re-reads the expired sign-ins (a status store changed).
    func reloadExpiredSignIns() async {
        await reloadExpiredSignIns(revealing: nil)
    }

    /// - Parameter signInId: an expired sign-in whose banner shows again
    ///   even if it was closed.
    private func reloadExpiredSignIns(revealing signInId: String?) async {
        // Accounts of a hidden store (Google Play while `googlePlayAccounts`
        // is OFF) never reach the banner, as in `checkExpiredAccounts()`.
        let accounts = featureFlags.visibleAccounts((try? await storage.fetchAll(AccountModel.self)) ?? [])
        let signIns = signInExpiry.expiredSignIns(in: accounts)
        if let signInId, let revealed = signIns.first(where: { $0.id == signInId }) {
            dismissedSignInAccountIds.subtract(revealed.accounts.map(\.id))
        }
        applyExpiredSignIns(signIns)
    }

    private func applyExpiredSignIns(_ allSignIns: [ExpiredSignIn]) {
        // An Apple ID signing in again on its own is no banner (its chips say
        // "Reconnecting…"); one waiting for its code asks for it.
        var signIns: [ExpiredSignIn] = []
        var awaitingCode: [String: AppleSessionCodeDestination] = [:]
        var reconnecting: [String] = []
        for signIn in allSignIns {
            guard case .appleId(let appleId) = signIn.provider, let state = autoReauth?.state(for: appleId) else {
                signIns.append(signIn)
                continue
            }
            switch state {
            case .reconnecting:
                reconnecting.append(AppleSessionKeychainStore.normalized(appleId))
                continue
            case .awaitingCode(let destination):
                awaitingCode[signIn.id] = destination
                signIns.append(signIn)
            }
        }
        uiState.awaitingCodeSignIns = awaitingCode
        uiState.expiredSignIns = signIns
        syncReconnectingAppleIds(adding: reconnecting)
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
            // The sheet resumes the automatic sign-in's code step on its own.
            let button: AnalyticsButton = uiState.awaitingCodeSignIns[signInId] == nil ? .signInAgain : .enterCode
            analytics.track(.buttonTap(button, on: .home))
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

    /// The Apple IDs of the "reconnecting" tip after a reload: keeps the
    /// ones the events added, adds the attempts already running when this
    /// ViewModel subscribed (`adding`), and drops any the reauthenticator no
    /// longer runs.
    private func syncReconnectingAppleIds(adding appleIds: [String]) {
        var ids = uiState.reconnectingAppleIds
        for appleId in appleIds where !ids.contains(appleId) {
            ids.append(appleId)
        }
        ids.removeAll { autoReauth?.state(for: $0) != .reconnecting }
        if ids != uiState.reconnectingAppleIds {
            uiState.reconnectingAppleIds = ids
        }
    }

    /// The automatic Apple ID sign-in: the "reconnecting" tip while it runs,
    /// and a toast once it succeeded (the reauthenticator then syncs the
    /// accounts). Apple
    /// sending a code shows the banner again, even if it was closed: the
    /// code waits for the user.
    private func autoReauthEvent(_ event: AppleSessionAutoReauthEvent) {
        switch event {
        case .started(let appleId):
            let id = AppleSessionKeychainStore.normalized(appleId)
            if !uiState.reconnectingAppleIds.contains(id) {
                uiState.reconnectingAppleIds.append(id)
            }
        case .finished(let appleId, let outcome):
            let id = AppleSessionKeychainStore.normalized(appleId)
            uiState.reconnectingAppleIds.removeAll { $0 == id }
            if outcome == .done {
                uiState.toastMessage = ToastMessage(
                    String(localized: "Apple account reconnected", comment: "Home toast once the app signed in again on its own to an expired Apple ID."),
                    icon: "checkmark.circle.fill"
                )
                // The accounts sync from `AppleSessionAutoReauthenticator`
                // (a follow-up run), not from here.
            }
            let revealed = outcome == .needsCode ? ExpiredSignIn.id(of: .appleId(appleId)) : nil
            Task { await reloadExpiredSignIns(revealing: revealed) }
        }
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
