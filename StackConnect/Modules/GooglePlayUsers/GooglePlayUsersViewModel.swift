import Foundation
import StackProtocols

// MARK: - Protocol

@MainActor
protocol GooglePlayUsersViewModelProtocol: ObservableObject {
    var uiState: GooglePlayUsersUiState { get set }
    func load() async
    func refresh() async
    /// Reloads from the cache only (after a pop-back from a user's detail,
    /// which keeps the cache in step with its writes).
    func reloadFromCache() async
    func saveDeveloperId() async
    /// Asks to remove `user`: a confirmation, or the reason it is refused.
    func requestRemove(_ user: GooglePlayUserModel)
    /// Asks to resend an expired invitation: a confirmation, or the reason it is refused.
    func requestResend(_ user: GooglePlayUserModel)
    func remove(_ user: GooglePlayUserModel) async
    func resend(_ user: GooglePlayUserModel) async
    /// Sends an invitation. Returns a user-facing error, `nil` once sent.
    func invite(_ form: GooglePlayInviteForm) async -> String?
}

// MARK: - Filter

/// The chips above the list (prototype 16).
enum GooglePlayUsersFilter: String, CaseIterable, Identifiable {
    case all
    case admins
    case invited
    case expired
    case serviceAccounts

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:             return String(localized: "All")
        case .admins:          return String(localized: "Admins", comment: "Google Play users filter.")
        case .invited:         return String(localized: "Invited", comment: "Google Play users list badge.")
        case .expired:         return String(localized: "Expired", comment: "Google Play users list badge.")
        case .serviceAccounts: return String(localized: "Service accounts", comment: "Google Play users filter.")
        }
    }

    func includes(_ user: GooglePlayUserModel) -> Bool {
        switch self {
        case .all:             return true
        case .admins:          return user.isAdmin
        case .invited:         return user.accessState == .invited
        case .expired:         return user.accessState.isExpired
        case .serviceAccounts: return user.isServiceAccount
        }
    }
}

// MARK: - UiState

struct GooglePlayUsersUiState {
    var account: AccountModel
    var users: [GooglePlayUserModel] = []
    var isLoading = false
    /// A load ran at least once (until then the list shows a spinner, not "No Users").
    var hasLoaded = false
    var isSyncing = false
    var showSyncToast = false
    /// Last load failure, user-facing.
    var error: String?
    /// Technical lines of `error`'s Share Error report.
    var errorDetails: [String] = []
    /// The last load failed in a way the developer ID explains (a wrong ID, or
    /// Google refusing the developer account; see
    /// `GooglePlayErrorTranslator.asksForDeveloperId`): the setup form comes
    /// back pre-filled with the stored ID, with `error` and a Retry (plan U3).
    var developerIdRejected = false
    var developerIdInput = ""
    var developerIdError: String?
    /// Technical lines of `developerIdError`'s Share Error report.
    var developerIdErrorDetails: [String] = []
    var isSavingDeveloperId = false
    var toastMessage: ToastMessage?
    /// The calling service account's `client_email` (self-protection, U7).
    var serviceAccountEmail: String?
    var searchQuery = ""
    var selectedFilter: GooglePlayUsersFilter = .all
    /// Remove confirmation on screen.
    var confirmRemove: GooglePlayUserModel?
    /// Resend confirmation on screen (plan U8).
    var confirmResend: GooglePlayUserModel?
    /// Why a requested change is refused (rules, scope, self-protection).
    var refusalMessage: String?
    /// A failed write, user-facing.
    var actionError: String?
    /// Technical lines of `actionError`'s Share Error report.
    var actionErrorDetails: [String] = []
    /// Technical lines of the last failed invitation (the invite sheet's
    /// Share Error report).
    var inviteErrorDetails: [String] = []
    /// E-mail of the user a write is running for.
    var workingEmail: String?
    var showInvite = false
    /// The account's apps in scope (cached list), for the invite sheet.
    var apps: [GooglePlayAppItem] = []

    /// "+" in the toolbar: the `users` add rule and a developer ID.
    var canShowInvite: Bool {
        access.canInvite && developerId != nil && !developerIdRejected
    }

    /// `users` narrowed by the filter chip and the search text (e-mail or name).
    var filteredUsers: [GooglePlayUserModel] {
        let query = searchQuery.trimmingCharacters(in: .whitespaces)
        return users.filter { user in
            selectedFilter.includes(user)
                && (query.isEmpty || user.email.localizedCaseInsensitiveContains(query)
                    || user.displayName.localizedCaseInsensitiveContains(query))
        }
    }

    var developerId: String? { account.googlePlayDeveloperId }

    /// Setup state: no developer ID, or the stored one was rejected.
    var showsSetup: Bool {
        developerId == nil || developerIdRejected
    }

    var access: GooglePlayUsersAccess {
        GooglePlayUsersAccess(account: account, serviceAccountEmail: serviceAccountEmail)
    }

    /// The developer ID setup footer: why the ID is asked for and who needs Admin.
    var developerIdFooter: String {
        switch account.authMethod {
        case .keyFile:
            return String(localized: "Google can't tell which developer account a service account belongs to: the ID is in Play Console › Settings › Developer account (and in every Play Console URL). The service account needs the “Admin (all permissions)” permission to manage users.")
        case .googleSignIn:
            return String(localized: "Google doesn't tell StackConnect which developer account to use: the ID is in Play Console › Settings › Developer account (and in every Play Console URL). The signed-in Google account needs the “Admin (all permissions)” permission to manage users.")
        }
    }
}

// MARK: - Implementation

/// The Users tab of a Google Play account (plan U4).
///
/// Offline-first: the cached users (`googleplay-users.{accountId}`) show right
/// away, then the list is fetched from `developers/{id}/users`. Nothing is
/// requested without a developer ID: the tab shows its setup field instead.
@MainActor
final class GooglePlayUsersViewModel: GooglePlayUsersViewModelProtocol {

    typealias ConnectionFactory = (GooglePlayCredentials) -> any GooglePlayUsersConnecting

    @Published var uiState: GooglePlayUsersUiState

    private let keychain: KeyStorable
    private let storage: PersistentStorable
    private let connectionFactory: ConnectionFactory
    private let analytics: AnalyticsTracking
    private var connection: (any GooglePlayUsersConnecting)?

    init(
        account: AccountModel,
        keychain: KeyStorable = KeychainStorable.shared,
        storage: PersistentStorable? = nil,
        connectionFactory: @escaping ConnectionFactory = { GooglePlayAccountConnection(credentials: $0) },
        analytics: AnalyticsTracking = AnalyticsService.shared
    ) {
        self.uiState = GooglePlayUsersUiState(account: account)
        self.keychain = keychain
        self.storage = storage ?? SwiftDataStorable.shared
        self.connectionFactory = connectionFactory
        self.analytics = analytics
        self.uiState.serviceAccountEmail = Self.serviceAccountEmail(keychain: keychain, accountId: account.id)
    }

    // MARK: - Load

    func load() async {
        await performLoad()
    }

    func refresh() async {
        await performLoad()
        analytics.track(.action(.refresh, on: .googlePlayUsers, result: uiState.error == nil ? .success : .failure))
    }

    func reloadFromCache() async {
        guard uiState.developerId != nil, let cached = await loadCache() else { return }
        uiState.users = Self.sorted(cached.users)
    }

    private func performLoad() async {
        defer { uiState.hasLoaded = true }
        // The ID the form already shows, if any (a Retry keeps what was typed).
        let shownRejectedId = uiState.developerIdRejected ? uiState.developerId : nil
        await refreshAccount()
        guard uiState.access.canView else { return }
        guard let developerId = uiState.developerId else {
            // Setup state: nothing to request until the ID is known.
            uiState.users = []
            uiState.isLoading = false
            uiState.developerIdRejected = false
            return
        }

        uiState.error = nil
        uiState.errorDetails = []
        await loadApps()
        if let cached = await loadCache() {
            uiState.users = Self.sorted(cached.users)
        }
        uiState.isLoading = uiState.users.isEmpty

        guard let connection = makeConnection() else {
            uiState.error = String(localized: "No credentials found for this account.")
            uiState.isLoading = false
            return
        }

        uiState.isSyncing = true
        if !uiState.users.isEmpty { uiState.showSyncToast = true }

        do {
            let users = try await connection.fetchUsers(developerId: developerId)
            uiState.users = Self.sorted(users)
            uiState.developerIdRejected = false
            await saveCache()
            Log.print.info("[GooglePlayUsers] Synced \(users.count) users for account: \(self.uiState.account.name)")
        } catch {
            let failure = GooglePlayErrorTranslator.usersFailure(error, call: usersCall(.list, developerId: developerId), logTag: "GooglePlayUsers", authMethod: uiState.account.authMethod)
            let offline = GooglePlayErrorTranslator.isOffline(error)
            if !(offline && !uiState.users.isEmpty) {
                uiState.error = failure.message
                uiState.errorDetails = failure.technicalDetails
            }
            let rejected = GooglePlayErrorTranslator.asksForDeveloperId(error)
            if rejected && shownRejectedId != developerId {
                // Ask again with the value as stored (verbatim, even one the
                // normalizer would refuse) so it can be corrected in place.
                uiState.developerIdInput = developerId
                uiState.developerIdError = nil
                uiState.developerIdErrorDetails = []
            }
            uiState.developerIdRejected = rejected
        }

        uiState.isLoading = false
        uiState.isSyncing = false
    }

    // MARK: - Developer ID (plan U3)

    func saveDeveloperId() async {
        analytics.track(.buttonTap(.saveDeveloperId, on: .googlePlayUsers))
        let input = uiState.developerIdInput
        guard let developerId = GooglePlayDeveloperId.normalized(input) else {
            // Say what's wrong (and keep the exact input for the report): a
            // pasted value often carries a URL without the ID or stray text.
            let details = GooglePlayDeveloperId.diagnosticLines(for: input, label: .entered)
            // The input isn't known to be an ID (it may be any pasted text): private.
            Log.print.error("[GooglePlayUsers] Developer ID refused by the normalizer — length: \(input.count, privacy: .public), input: \"\(input)\"")
            uiState.developerIdError = GooglePlayDeveloperId.invalidMessage
            uiState.developerIdErrorDetails = details
            return
        }
        uiState.isSavingDeveloperId = true
        defer { uiState.isSavingDeveloperId = false }

        // The same ID again (a rejected one re-entered as is): just retry.
        let changed = developerId != uiState.developerId
        if changed {
            let updated = uiState.account.updating(googlePlayDeveloperId: .some(developerId))
            do {
                try await storage.save(updated, id: updated.id)
            } catch {
                Log.print.error("[GooglePlayUsers] Saving the developer ID \"\(developerId, privacy: .public)\" failed: \(error.localizedDescription, privacy: .public)")
                uiState.developerIdError = String(localized: "The Developer ID couldn't be saved. Try again.") + "\n" + error.localizedDescription
                uiState.developerIdErrorDetails = GooglePlayDeveloperId.diagnosticLines(for: input, label: .entered)
                analytics.track(.action(.saveDeveloperId, on: .googlePlayUsers, result: .failure))
                return
            }
            uiState.account = updated
        }
        // The field shows the ID as stored (a pasted Console URL becomes the
        // number); a rejected form stays up, Save spinning, until the reload ends.
        uiState.developerIdInput = developerId
        uiState.developerIdError = nil
        uiState.developerIdErrorDetails = []
        analytics.track(.action(.saveDeveloperId, on: .googlePlayUsers, result: .success))

        // Another developer account's users must not show under the new ID.
        if changed {
            uiState.users = []
            try? await storage.delete(GooglePlayUsersCache.self, id: cacheKey)
        }
        await performLoad()
    }

    // MARK: - Remove / Resend (plan U4, U8)

    func requestRemove(_ user: GooglePlayUserModel) {
        analytics.track(.buttonTap(.remove, on: .googlePlayUsers))
        if let refusal = uiState.access.removeRefusal(for: user) {
            uiState.refusalMessage = GooglePlayUsersAccess.message(for: refusal)
        } else {
            uiState.confirmRemove = user
        }
    }

    func requestResend(_ user: GooglePlayUserModel) {
        analytics.track(.buttonTap(.resendInvite, on: .googlePlayUsers))
        if let refusal = uiState.access.resendRefusal(for: user) {
            uiState.refusalMessage = GooglePlayUsersAccess.message(for: refusal)
        } else {
            uiState.confirmResend = user
        }
    }

    /// Deletes the user on Google Play, then from the list and the cache. A
    /// failure changes nothing locally.
    func remove(_ user: GooglePlayUserModel) async {
        uiState.confirmRemove = nil
        guard uiState.access.removeRefusal(for: user) == nil,
              let developerId = uiState.developerId, let connection = makeConnection() else { return }
        uiState.workingEmail = user.email
        defer { uiState.workingEmail = nil }
        do {
            try await connection.deleteUser(developerId: developerId, email: user.email)
            uiState.users.removeAll { $0.id == user.id }
            await saveCache()
            uiState.toastMessage = ToastMessage(user.accessState.isPendingInvitation
                                                ? String(localized: "Invitation cancelled")
                                                : String(localized: "User removed"))
            analytics.track(.action(.deleteUser, on: .googlePlayUsers, result: .success))
        } catch {
            let failure = GooglePlayErrorTranslator.usersFailure(
                error, call: usersCall(.delete, developerId: developerId, email: user.email), logTag: "GooglePlayUsers",
                authMethod: uiState.account.authMethod
            )
            showActionError(failure)
            analytics.track(.action(.deleteUser, on: .googlePlayUsers, result: .failure))
        }
    }

    /// Google has no resend: the expired invitation is deleted and the same
    /// permissions, app access and (future) expiry are invited again (plan U8).
    func resend(_ user: GooglePlayUserModel) async {
        uiState.confirmResend = nil
        guard uiState.access.resendRefusal(for: user) == nil,
              let developerId = uiState.developerId, let connection = makeConnection() else { return }
        uiState.workingEmail = user.email
        defer { uiState.workingEmail = nil }

        do {
            try await connection.deleteUser(developerId: developerId, email: user.email)
        } catch {
            Log.print.error("[GooglePlayUsers] Resend failed removing the old invitation")
            let failure = GooglePlayErrorTranslator.usersFailure(
                error, call: usersCall(.delete, developerId: developerId, email: user.email), logTag: "GooglePlayUsers",
                authMethod: uiState.account.authMethod
            )
            showActionError(failure)
            analytics.track(.action(.resendInvite, on: .googlePlayUsers, result: .failure))
            return
        }

        let expiration = user.expirationTime.flatMap { $0 > Date() ? $0 : nil }
        do {
            let invited = try await connection.inviteUser(
                developerId: developerId,
                email: user.email,
                accountPermissions: user.developerAccountPermissions,
                grants: user.grants,
                expiration: expiration
            )
            replace(user, with: invited)
            await saveCache()
            uiState.toastMessage = ToastMessage(String(localized: "Invitation sent again to \(user.email)"), icon: "envelope.fill")
            analytics.track(.action(.resendInvite, on: .googlePlayUsers, result: .success))
        } catch {
            // The old invitation is gone: the list must say so too.
            Log.print.error("[GooglePlayUsers] Resend failed sending the new invitation")
            let failure = GooglePlayErrorTranslator.usersFailure(error, call: usersCall(.invite, developerId: developerId), logTag: "GooglePlayUsers", authMethod: uiState.account.authMethod)
            uiState.users.removeAll { $0.id == user.id }
            await saveCache()
            let reason = failure.message
            showActionError(GooglePlayUsersFailure(
                message: String(localized: "The expired invitation was removed, but the new one couldn't be sent. Invite \(user.email) again.\n\(reason)"),
                technicalDetails: failure.technicalDetails
            ))
            analytics.track(.action(.resendInvite, on: .googlePlayUsers, result: .failure))
        }
    }

    // MARK: - Invite (plan U6)

    func invite(_ form: GooglePlayInviteForm) async -> String? {
        uiState.inviteErrorDetails = []
        let access = uiState.access
        guard access.canInvite else { return GooglePlayUsersAccess.message(for: .notPermitted) }
        guard form.isEmailValid else { return String(localized: "Enter a valid e-mail address.") }
        guard form.hasAccess else { return String(localized: "Turn on an account permission or add an app.") }
        if !form.accountPermissions.isEmpty, !access.canInviteWithAccountPermissions {
            return GooglePlayUsersAccess.message(for: .outsideScope)
        }
        if form.grants.contains(where: { !access.allowsApp($0.packageName) }) {
            return GooglePlayUsersAccess.message(for: .outsideScope)
        }
        let email = form.trimmedEmail
        if uiState.users.contains(where: { $0.matches(email: email) }) {
            return String(localized: "This person already has access to this developer account or has a pending invitation.")
        }
        guard let developerId = uiState.developerId, let connection = makeConnection() else {
            return String(localized: "No credentials found for this account.")
        }
        do {
            let invited = try await connection.inviteUser(
                developerId: developerId,
                email: email,
                accountPermissions: form.normalizedAccountPermissions,
                grants: form.grants,
                expiration: form.expiration
            )
            replace(invited, with: invited)
            await saveCache()
            uiState.toastMessage = ToastMessage(String(localized: "Invitation sent to \(email)"), icon: "envelope.fill")
            analytics.track(.action(.inviteUser, on: .googlePlayInviteUser, result: .success))
            return nil
        } catch {
            let failure = GooglePlayErrorTranslator.usersFailure(error, call: usersCall(.invite, developerId: developerId), logTag: "GooglePlayUsers", authMethod: uiState.account.authMethod)
            uiState.inviteErrorDetails = failure.technicalDetails
            analytics.track(.action(.inviteUser, on: .googlePlayInviteUser, result: .failure))
            return failure.message
        }
    }

    private func loadApps() async {
        let apps = (try? await storage.fetch([GooglePlayAppItem].self, id: GooglePlayAppItem.cacheKey(accountId: uiState.account.id))) ?? []
        uiState.apps = apps
            .filter { uiState.account.allowsApp(bundleId: $0.packageName) }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    private func replace(_ user: GooglePlayUserModel, with updated: GooglePlayUserModel) {
        var users = uiState.users.filter { $0.id != user.id && $0.id != updated.id }
        users.append(updated)
        uiState.users = Self.sorted(users)
    }

    // MARK: - Private

    private func usersCall(_ method: GooglePlayUsersCall.Method, developerId: String, email: String? = nil) -> GooglePlayUsersCall {
        GooglePlayUsersCall(method, developerId: developerId, email: email, serviceAccountEmail: uiState.serviceAccountEmail)
    }

    private func showActionError(_ failure: GooglePlayUsersFailure) {
        uiState.actionError = failure.message
        uiState.actionErrorDetails = failure.technicalDetails
    }

    /// The account as stored now: the developer ID may have been set in
    /// Account Settings since this screen was pushed.
    private func refreshAccount() async {
        if let stored = try? await storage.fetch(AccountModel.self, id: uiState.account.id) {
            uiState.account = stored
        }
    }

    private func makeConnection() -> (any GooglePlayUsersConnecting)? {
        if let connection { return connection }
        guard let credentials: GooglePlayCredentials = keychain.object(forKey: "credentials.\(uiState.account.id)") else {
            Log.print.error("[GooglePlayUsers] No credentials found for account: \(self.uiState.account.name)")
            return nil
        }
        let made = connectionFactory(credentials)
        connection = made
        return made
    }

    private static func serviceAccountEmail(keychain: KeyStorable, accountId: String) -> String? {
        guard let credentials: GooglePlayCredentials = keychain.object(forKey: "credentials.\(accountId)") else { return nil }
        return (try? GooglePlayServiceAccount(credentials: credentials))?.clientEmail
    }

    private var cacheKey: String {
        GooglePlayUsersCache.cacheKey(accountId: uiState.account.id)
    }

    private func loadCache() async -> GooglePlayUsersCache? {
        do {
            return try await storage.fetch(GooglePlayUsersCache.self, id: cacheKey)
        } catch {
            Log.print.error("[GooglePlayUsers] Cache load failed: \(error.localizedDescription)")
            return nil
        }
    }

    private func saveCache() async {
        let cache = GooglePlayUsersCache(accountId: uiState.account.id, users: uiState.users, fetchedAt: Date())
        do {
            try await storage.save(cache, id: cacheKey)
        } catch {
            Log.print.error("[GooglePlayUsers] Cache save failed: \(error.localizedDescription)")
        }
    }

    /// People with access first (by name), then invitations, expired ones, and
    /// service accounts last.
    static func sorted(_ users: [GooglePlayUserModel]) -> [GooglePlayUserModel] {
        func rank(_ user: GooglePlayUserModel) -> Int {
            if user.isServiceAccount { return 3 }
            switch user.accessState {
            case .invited: return 1
            case .invitationExpired, .accessExpired: return 2
            default: return 0
            }
        }
        return users.sorted { lhs, rhs in
            let (l, r) = (rank(lhs), rank(rhs))
            if l != r { return l < r }
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
    }
}
