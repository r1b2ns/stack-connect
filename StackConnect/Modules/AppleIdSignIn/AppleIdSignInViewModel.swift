import Foundation
import StackProtocols
import StackCoreRust

// MARK: - Protocol

@MainActor
protocol AppleIdSignInViewModelProtocol: ObservableObject {
    var uiState: AppleIdSignInUiState { get set }

    /// Sends the Apple ID and password to Apple (screen 1): the typed one, or
    /// the one saved on the device when `uiState.usesSavedPassword`. The typed
    /// password is cleared from the state right away.
    func signIn() async
    /// The screen appeared: when signing in again and a password is saved for
    /// the Apple ID, signs in with it straight away, so only the code is left
    /// to type. Runs once per screen.
    func signInWithSavedPasswordIfAvailable() async
    /// The Apple ID field changed (Add Account): offers the password saved for
    /// that Apple ID, if any.
    func emailDidChange()
    /// "Use a different password": back to the password field, without the
    /// saved password (which stays saved until a sign-in replaces it).
    func useDifferentPassword()
    /// "Save password on this device": whether the typed password is kept in
    /// the Keychain once the sign-in finished. Off also removes a password
    /// saved earlier for the Apple ID (once the sign-in finished).
    func setSavesPassword(_ savesPassword: Bool)
    /// Stores the typed code (digits only, up to `codeLength`) and submits it
    /// once complete (screen 2).
    func updateCode(_ code: String) async
    func submitCode() async
    /// "Send SMS instead": texts a code to the trusted phone `phoneId`.
    func requestSms(phoneId: UInt64) async
    /// Back from the code (or acknowledgement) screen to the Apple ID form.
    func startOver()
    func toggleTeam(_ id: UInt64)
    func setAllTeamsSelected(_ selected: Bool)
    /// Adds one account per selected team (screen 3).
    func save() async
    /// Tracks the tap. - Returns: appleid.apple.com, for the view to open.
    func openAppleIdWebsite() -> URL?
    /// The screen went away: a sign-in left unfinished is reported as cancelled.
    func discard()
}

// MARK: - Mode

/// What the sign-in is for.
enum AppleIdSignInMode: Equatable {
    /// Add Account: sign in, then pick the teams to add.
    case addAccounts
    /// The session of `appleId` expired: sign in again with the same Apple ID
    /// and replace its session for every team account (plan D5).
    case signInAgain(appleId: String)
}

// MARK: - UiState

struct AppleIdSignInUiState: Equatable {

    enum Step: Equatable {
        /// Screen 1: Apple ID and password.
        case credentials
        /// Screen 2: the two-factor code.
        case code
        /// Screen 3: the teams to add (Add Account only).
        case teams
        /// Apple wants the user to act at appleid.apple.com first.
        case needsAcknowledgement
        /// Accounts added, or the session renewed.
        case finished
    }

    struct TeamItem: Identifiable, Equatable {
        let team: AppleTeam
        /// Already added with this Apple ID: shown, not selectable.
        let isAlreadyAdded: Bool
        var id: UInt64 { team.providerId }
    }

    let mode: AppleIdSignInMode
    var step: Step = .credentials

    var email: String
    /// Bound to the secure field only. Cleared from the state as soon as it is
    /// sent to the core, and never logged. The ViewModel saves it in the
    /// Keychain (`ApplePasswordKeychainStore`) once the sign-in finished.
    var password = ""
    /// A password is saved on this device for `email`, and this sign-in uses
    /// it: the password field is hidden ("Use a different password" shows it).
    var usesSavedPassword = false
    /// "Save password on this device" (on by default, so it is also on when a
    /// password is already saved for the Apple ID). Applied only once the
    /// sign-in finished, also when the saved password is used: off then
    /// removes it. Never reset when the saved-password row comes and goes.
    var savesPassword = true

    var code = ""
    var codeLength = AppleIdSignInUiState.defaultCodeLength
    var phones: [AppleTrustedPhone] = []
    /// Where the code to type was sent; `nil` until one was sent.
    var codeMethod: AppleCodeMethod?

    var teams: [TeamItem] = []
    var selectedTeamIds: Set<UInt64> = []

    var isWorking = false
    /// A failure shown on the current screen.
    var errorMessage: String?
    /// A wrong code: shown under the code field, the sign-in keeps waiting.
    var codeError: String?
    /// Information, e.g. where the code was sent.
    var notice: String?

    static let defaultCodeLength = 6

    init(mode: AppleIdSignInMode) {
        self.mode = mode
        if case .signInAgain(let appleId) = mode {
            self.email = appleId
        } else {
            self.email = ""
        }
    }

    /// The Apple ID is fixed when signing in again: the session must stay the
    /// one of the accounts that use it.
    var isEmailEditable: Bool { mode == .addAccounts }

    var canSignIn: Bool {
        step == .credentials && !isWorking
            && !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (usesSavedPassword || !password.isEmpty)
    }

    var canSubmitCode: Bool {
        step == .code && !isWorking && codeMethod != nil && code.count == codeLength
    }

    var selectableTeams: [TeamItem] { teams.filter { !$0.isAlreadyAdded } }

    var areAllTeamsSelected: Bool {
        let selectable = selectableTeams
        return !selectable.isEmpty && selectable.allSatisfy { selectedTeamIds.contains($0.id) }
    }

    /// Save adds the selected teams, or, when every team is already added,
    /// only renews the session they share.
    var canSave: Bool {
        guard step == .teams, !isWorking, !teams.isEmpty else { return false }
        return !selectedTeamIds.isEmpty || selectableTeams.isEmpty
    }

    /// The phone the last text message went to.
    var smsPhone: AppleTrustedPhone? {
        guard case .phone(let id)? = codeMethod else { return nil }
        return phones.first { $0.id == id }
    }
}

// MARK: - Implementation

@MainActor
final class AppleIdSignInViewModel: AppleIdSignInViewModelProtocol {

    /// Builds the core's sign-in: a fresh one, or one over the saved session
    /// (its trust cookie can spare the code when signing in again).
    typealias SignInFactory = (_ savedSession: Data?) throws -> any AppleIdSignInProtocol

    static let appleIdWebsite = URL(string: "https://appleid.apple.com")

    @Published var uiState: AppleIdSignInUiState

    private let storage: PersistentStorable
    private let keychain: KeyStorable
    private let sessionStore: AppleSessionKeychainStore
    private let passwordStore: ApplePasswordKeychainStore
    private let sessionStatus: AppleSessionStatusTracking
    private let roleResolver: any AppleSessionRoleResolving
    private let analytics: AnalyticsTracking
    private let makeSignIn: SignInFactory

    /// The core's sign-in in progress.
    private var flow: (any AppleIdSignInProtocol)?
    /// The password `flow` was started with, kept in memory only until the
    /// sign-in finished, to be saved then (never before Apple accepted it).
    private var pendingPassword: String?
    private var hasStarted = false
    private var hasConcluded = false
    private var hasTriedSavedPassword = false
    /// Apple IDs whose saved password the user chose not to use (Add Account).
    private var declinedSavedPassword = Set<String>()

    init(
        mode: AppleIdSignInMode,
        storage: PersistentStorable? = nil,
        keychain: KeyStorable = KeychainStorable.shared,
        sessionStatus: AppleSessionStatusTracking = AppleSessionStatusStore.shared,
        roleResolver: (any AppleSessionRoleResolving)? = nil,
        analytics: AnalyticsTracking = AnalyticsService.shared,
        makeSignIn: SignInFactory? = nil
    ) {
        self.uiState = AppleIdSignInUiState(mode: mode)
        self.storage = storage ?? SwiftDataStorable.shared
        self.keychain = keychain
        self.sessionStore = AppleSessionKeychainStore(keychain: keychain)
        self.passwordStore = ApplePasswordKeychainStore(keychain: keychain)
        self.sessionStatus = sessionStatus
        self.roleResolver = roleResolver ?? AppleSessionRoleResolver()
        self.analytics = analytics
        self.makeSignIn = makeSignIn ?? Self.coreSignIn
    }

    private static func coreSignIn(_ savedSession: Data?) throws -> any AppleIdSignInProtocol {
        if let savedSession {
            return try AppleIdSignIn.withSavedSession(blob: savedSession)
        }
        return try AppleIdSignIn()
    }

    private var appleId: String { AppleSessionKeychainStore.normalized(uiState.email) }

    // MARK: - Screen 1: Apple ID and password

    func signIn() async {
        guard uiState.step == .credentials, !uiState.isWorking else { return }
        analytics.track(.buttonTap(.signInWithAppleId, on: .appleIdSignIn))
        await performSignIn()
    }

    func signInWithSavedPasswordIfAvailable() async {
        guard !hasTriedSavedPassword else { return }
        hasTriedSavedPassword = true
        guard case .signInAgain = uiState.mode, uiState.step == .credentials, !uiState.isWorking,
              passwordStore.hasPassword(for: appleId) else {
            emailDidChange()
            return
        }
        Log.print.info("[AppleIdSignIn] Signing in again with the saved password")
        uiState.usesSavedPassword = true
        await performSignIn()
    }

    func emailDidChange() {
        guard uiState.step == .credentials, !uiState.isWorking else { return }
        let id = appleId
        uiState.usesSavedPassword = !id.isEmpty
            && !declinedSavedPassword.contains(id)
            && passwordStore.hasPassword(for: id)
    }

    func useDifferentPassword() {
        guard uiState.usesSavedPassword, !uiState.isWorking,
              uiState.step == .credentials || uiState.step == .code else { return }
        analytics.track(.buttonTap(.useDifferentPassword, on: .appleIdSignIn))
        declinedSavedPassword.insert(appleId)
        uiState.usesSavedPassword = false
        if uiState.step == .code {
            // The code belongs to the saved password's attempt: start over.
            resetToCredentials()
        }
    }

    func setSavesPassword(_ savesPassword: Bool) {
        guard uiState.savesPassword != savesPassword, uiState.step == .credentials, !uiState.isWorking else { return }
        analytics.track(.buttonTap(savesPassword ? .savePasswordOn : .savePasswordOff, on: .appleIdSignIn))
        uiState.savesPassword = savesPassword
    }

    private func performSignIn() async {
        let email = uiState.email.trimmingCharacters(in: .whitespacesAndNewlines)
        let usesSavedPassword = uiState.usesSavedPassword
        // The password goes to the core once, from this local: the state that
        // backs the secure field is cleared before the call.
        let password = usesSavedPassword ? (passwordStore.password(for: email) ?? "") : uiState.password
        uiState.password = ""
        if usesSavedPassword, password.isEmpty {
            // Removed meanwhile (e.g. the account was deleted): ask for it.
            uiState.usesSavedPassword = false
        }
        guard !email.isEmpty, !password.isEmpty else {
            uiState.errorMessage = String(localized: "Enter your Apple ID and password.")
            return
        }

        analytics.track(.action(.appleIdSignInStarted, on: .appleIdSignIn, parameters: modeParameters))
        hasStarted = true
        uiState.errorMessage = nil
        uiState.notice = nil
        uiState.isWorking = true
        defer { uiState.isWorking = false }

        do {
            let flow = try makeSignIn(savedSession())
            self.flow = flow
            pendingPassword = password
            let step = try await flow.start(email: email, password: password)
            await handle(step)
        } catch {
            endFlow()
            if usesSavedPassword, Self.isWrongPassword(error) {
                savedPasswordRefused(appleId: email)
                trackSignIn(.failure, failure: .invalidCredentials)
            } else {
                fail(error, message: Self.message(for: error, stage: .password))
            }
        }
    }

    /// Apple refused the saved password (`AppleSignInError::WrongCredentials`,
    /// `StackError.InvalidCredentials` from `start`): it likely changed. Forget
    /// it and ask for the current one.
    private func savedPasswordRefused(appleId email: String) {
        Log.print.notice("[AppleIdSignIn] Apple refused the saved password: removed it from the Keychain")
        passwordStore.deletePassword(for: email)
        uiState.usesSavedPassword = false
        uiState.step = .credentials
        uiState.errorMessage = nil
        uiState.notice = String(localized: "The saved password didn't work. It may have changed: enter your current Apple ID password.",
                                comment: "Apple ID sign-in, password screen: the password saved on the device was refused by Apple and removed.")
    }

    /// `start`'s `InvalidCredentials` is a wrong Apple ID or password (the
    /// core maps a wrong code to it only from `submitCode`).
    static func isWrongPassword(_ error: Error) -> Bool {
        if case StackError.InvalidCredentials? = error as? StackError { return true }
        return false
    }

    // MARK: - Screen 2: two-factor code

    func updateCode(_ code: String) async {
        let digits = String(code.filter(\.isNumber).prefix(uiState.codeLength))
        guard digits != uiState.code else { return }
        uiState.code = digits
        if !digits.isEmpty { uiState.codeError = nil }
        if uiState.canSubmitCode {
            await submitCode()
        }
    }

    func submitCode() async {
        guard uiState.canSubmitCode, let method = uiState.codeMethod, let flow else { return }
        analytics.track(.buttonTap(.submitCode, on: .appleIdSignIn))
        let code = uiState.code
        uiState.errorMessage = nil
        uiState.codeError = nil
        uiState.isWorking = true
        defer { uiState.isWorking = false }

        do {
            let step = try await flow.submitCode(code: code, method: method)
            uiState.code = ""
            await handle(step)
        } catch StackError.InvalidCredentials {
            // A wrong code: the core keeps waiting for one, so stay here.
            Log.print.notice("[AppleIdSignIn] Apple refused the two-factor code")
            uiState.code = ""
            uiState.codeError = String(localized: "That code isn't right. Check it and try again.")
            trackSignIn(.failure, failure: .invalidCredentials)
        } catch {
            fail(error, message: Self.message(for: error, stage: .code))
        }
    }

    func requestSms(phoneId: UInt64) async {
        guard uiState.step == .code, !uiState.isWorking, let flow else { return }
        analytics.track(.buttonTap(.sendSms, on: .appleIdSignIn))
        uiState.errorMessage = nil
        uiState.codeError = nil
        uiState.isWorking = true
        defer { uiState.isWorking = false }

        do {
            let step = try await flow.requestSms(phoneId: phoneId)
            analytics.track(.action(.appleIdCodeRequested, on: .appleIdSignIn, result: .success))
            uiState.code = ""
            await handle(step)
            // The code now goes to that phone, whatever the step says.
            if uiState.step == .code {
                uiState.codeMethod = .phone(phoneId: phoneId)
                uiState.notice = smsNotice()
            }
        } catch {
            Log.print.error("[AppleIdSignIn] Requesting a text message failed: \(error.localizedDescription, privacy: .public)")
            analytics.track(.action(.appleIdCodeRequested, on: .appleIdSignIn, result: .failure,
                                    parameters: AnalyticsErrorCategory.parameters(for: error)))
            uiState.errorMessage = Self.message(for: error, stage: .code)
        }
    }

    func startOver() {
        guard uiState.step == .code || uiState.step == .needsAcknowledgement, !uiState.isWorking else { return }
        analytics.track(.buttonTap(.back, on: .appleIdSignIn))
        resetToCredentials()
    }

    private func resetToCredentials() {
        endFlow()
        uiState.step = .credentials
        uiState.code = ""
        uiState.codeMethod = nil
        uiState.phones = []
        uiState.codeError = nil
        uiState.errorMessage = nil
        uiState.notice = nil
    }

    // MARK: - Screen 3: teams

    func toggleTeam(_ id: UInt64) {
        guard uiState.selectableTeams.contains(where: { $0.id == id }) else { return }
        analytics.track(.buttonTap(.toggleTeam, on: .appleIdSignIn))
        if uiState.selectedTeamIds.contains(id) {
            uiState.selectedTeamIds.remove(id)
        } else {
            uiState.selectedTeamIds.insert(id)
        }
    }

    func setAllTeamsSelected(_ selected: Bool) {
        analytics.track(.buttonTap(selected ? .selectAll : .selectNone, on: .appleIdSignIn))
        uiState.selectedTeamIds = selected ? Set(uiState.selectableTeams.map(\.id)) : []
    }

    func save() async {
        guard uiState.mode == .addAccounts, uiState.canSave else { return }
        analytics.track(.buttonTap(.save, on: .appleIdSignIn))
        let selected = uiState.selectableTeams.filter { uiState.selectedTeamIds.contains($0.id) }
        uiState.errorMessage = nil
        uiState.isWorking = true
        defer { uiState.isWorking = false }

        guard await storeSession() else {
            trackCreateAccount(.failure, count: 0, failure: .unknown)
            return
        }

        var saved = 0
        for item in selected {
            let reference = AppleWebSessionReference(appleId: appleId, teamId: item.team.providerId, teamName: item.team.name)
            let role = await roleResolver.role(of: appleId, in: reference)
            let account = AccountModel(
                name: item.team.name,
                providerType: .apple,
                role: role,
                authMethod: .appleIdSignIn
            )
            let key = "credentials.\(account.id)"
            keychain.setObject(AppleCredentials(webSession: reference), forKey: key)
            do {
                try await storage.save(account, id: account.id)
                saved += 1
            } catch {
                keychain.removeObject(forKey: key)
                Log.print.error("[AppleIdSignIn] Saving an Apple ID account failed: \(error.localizedDescription, privacy: .public)")
                uiState.errorMessage = error.userFacingMessage
                if saved > 0 { AccountsChange.post() }
                trackCreateAccount(.failure, count: saved, failure: .storage)
                return
            }
        }

        AccountsChange.post()
        Log.print.info("[AppleIdSignIn] Added \(saved, privacy: .public) App Store Connect account(s) with an Apple ID")
        trackCreateAccount(.success, count: saved)
        conclude()
    }

    func openAppleIdWebsite() -> URL? {
        analytics.track(.buttonTap(.openAppleIdWebsite, on: .appleIdSignIn))
        return Self.appleIdWebsite
    }

    func discard() {
        guard hasStarted, !hasConcluded else { return }
        hasConcluded = true
        endFlow()
        uiState.password = ""
        Log.print.info("[AppleIdSignIn] Closed before the end")
        trackSignIn(.cancelled)
    }

    // MARK: - Steps

    private func handle(_ step: AppleSignInStep) async {
        uiState.errorMessage = nil
        switch step {
        case let .needsCode(methods, phones, codeLength, delivery):
            showCode(methods: methods, phones: phones, codeLength: codeLength, delivery: delivery)
        case .needsAcknowledgement:
            Log.print.notice("[AppleIdSignIn] The Apple ID needs action at appleid.apple.com")
            endFlow()
            uiState.step = .needsAcknowledgement
            trackSignIn(.failure, failure: .forbidden)
        case .done(let teams):
            await signedIn(teams: teams)
        }
    }

    private func showCode(methods: [AppleCodeMethod], phones: [AppleTrustedPhone], codeLength: UInt8, delivery: AppleCodeDelivery) {
        uiState.step = .code
        uiState.code = ""
        uiState.codeError = nil
        uiState.phones = phones
        // A sane field even if Apple sends something odd.
        uiState.codeLength = (4...10).contains(Int(codeLength)) ? Int(codeLength) : AppleIdSignInUiState.defaultCodeLength
        switch delivery {
        case .trustedDevices:
            uiState.codeMethod = .trustedDevice
            uiState.notice = String(localized: "Enter the code shown on your Apple devices.")
        case .phone(let phoneId):
            uiState.codeMethod = .phone(phoneId: phoneId)
            uiState.notice = smsNotice()
        case .notSent:
            uiState.codeMethod = methods.contains(.trustedDevice) ? .trustedDevice : nil
            uiState.notice = String(localized: "Apple didn't send a code yet. Choose a phone number below to get one by text message.")
        }
    }

    private func smsNotice() -> String {
        if let phone = uiState.smsPhone {
            return String(localized: "Enter the code sent to \(phone.maskedNumber).",
                          comment: "Apple ID sign-in, code screen. The placeholder is the masked trusted phone number, e.g. +49 •••• •••••85.")
        }
        return String(localized: "Enter the code sent to your phone.")
    }

    private func signedIn(teams: [AppleTeam]) async {
        flowSucceeded(teamCount: teams.count)
        switch uiState.mode {
        case .signInAgain:
            guard await storeSession() else { return }
            Log.print.info("[AppleIdSignIn] Signed in again: the Apple ID session was replaced")
            conclude()
        case .addAccounts:
            await showTeams(teams)
        }
    }

    private func showTeams(_ teams: [AppleTeam]) async {
        let all = (try? await storage.fetchAll(AccountModel.self)) ?? []
        let existing = AppleSessionReferences.accounts(using: appleId, in: all, keychain: keychain)
        let addedTeamIds = Set(existing.compactMap { AppleSessionReferences.reference(of: $0, keychain: keychain)?.teamId })

        uiState.teams = teams.map {
            AppleIdSignInUiState.TeamItem(team: $0, isAlreadyAdded: addedTeamIds.contains($0.providerId))
        }
        uiState.selectedTeamIds = Set(uiState.selectableTeams.map(\.id))
        uiState.step = .teams
        uiState.notice = existing.isEmpty ? nil
            : String(localized: "Teams already added with this Apple ID are marked. Saving also renews their sign-in.")
        if teams.isEmpty {
            uiState.errorMessage = String(localized: "This Apple ID isn't a member of any App Store Connect team.")
        }
    }

    /// Ends the core's sign-in and keeps the session in the Apple ID's shared
    /// Keychain item, and the password Apple just accepted in its own item.
    /// - Returns: whether it was stored.
    private func storeSession() async -> Bool {
        guard let flow else { return false }
        do {
            let blob = try await flow.finish()
            sessionStore.save(accountId: appleId, blob: blob)
            storePassword()
            endFlow()
            sessionStatus.markValid(appleId: appleId)
            return true
        } catch {
            Log.print.error("[AppleIdSignIn] Finishing the sign-in failed: \(error.localizedDescription, privacy: .public)")
            uiState.errorMessage = Self.message(for: error, stage: .password)
            return false
        }
    }

    /// Applies "Save password on this device" once Apple accepted the
    /// password: saves (or refreshes, when the saved one was used) it when
    /// on; otherwise removes any password saved earlier for the Apple ID.
    /// An explicit off is honored even when the saved password was used for
    /// this sign-in. Signing in again with the saved password never shows
    /// the toggle, so it stays on there and the password is refreshed.
    private func storePassword() {
        if uiState.savesPassword {
            guard let pendingPassword else { return }
            passwordStore.save(pendingPassword, for: appleId)
            Log.print.info("[AppleIdSignIn] Saved the Apple ID password in the Keychain")
        } else if passwordStore.hasPassword(for: appleId) {
            passwordStore.deletePassword(for: appleId)
            Log.print.info("[AppleIdSignIn] Not saving the Apple ID password: removed the one saved earlier")
        }
    }

    /// Drops the core's sign-in and the password kept for it.
    private func endFlow() {
        flow = nil
        pendingPassword = nil
    }

    private func conclude() {
        hasConcluded = true
        uiState.step = .finished
    }

    /// A failure that ends this attempt: back to where it can be retried.
    private func fail(_ error: Error, message: String) {
        Log.print.error("[AppleIdSignIn] Sign-in failed: \(error.localizedDescription, privacy: .public)")
        uiState.errorMessage = message
        trackSignIn(.failure, failure: AnalyticsErrorCategory(connectionError: error))
    }

    private func savedSession() -> Data? {
        guard case .signInAgain = uiState.mode else { return nil }
        return sessionStore.load(accountId: appleId)
    }

    // MARK: - Analytics

    private var modeParameters: [String: AnalyticsValue] {
        let reauth: Bool
        if case .signInAgain = uiState.mode { reauth = true } else { reauth = false }
        return [AnalyticsParameterKey.trigger: .string(reauth ? "sign_in_again" : "add_account")]
    }

    private func flowSucceeded(teamCount: Int) {
        var parameters = modeParameters
        parameters[AnalyticsParameterKey.count] = .int(teamCount)
        analytics.track(.action(.appleIdSignIn, on: .appleIdSignIn, result: .success, parameters: parameters))
    }

    private func trackSignIn(_ result: AnalyticsResult, failure: AnalyticsErrorCategory? = nil) {
        var parameters = modeParameters
        if let failure {
            parameters.merge(failure.parameters) { _, category in category }
        }
        analytics.track(.action(.appleIdSignIn, on: .appleIdSignIn, result: result, parameters: parameters))
    }

    private func trackCreateAccount(_ result: AnalyticsResult, count: Int, failure: AnalyticsErrorCategory? = nil) {
        var parameters: [String: AnalyticsValue] = [
            AnalyticsParameterKey.kind: .string(ProviderType.apple.rawValue),
            AnalyticsParameterKey.authMethod: .string(AccountAuthMethod.appleIdSignIn.analyticsValue),
            AnalyticsParameterKey.count: .int(count)
        ]
        if let failure {
            parameters.merge(failure.parameters) { _, category in category }
        }
        analytics.track(.action(.createAccount, on: .appleIdSignIn, result: result, parameters: parameters))
    }

    // MARK: - Copy

    enum Stage { case password, code }

    /// The user-facing message of a failed step. Never repeats what the user
    /// typed; the core's own text is appended only for `.Auth` (it names the
    /// cause, e.g. a locked Apple ID or an unsupported second factor).
    static func message(for error: Error, stage: Stage) -> String {
        if OfflineError.isConnectivityFailure(error) {
            return String(localized: "Couldn't reach Apple. Check your connection and try again.")
        }
        guard let stackError = error as? StackError else {
            return error.userFacingMessage
        }
        switch stackError {
        case .InvalidCredentials:
            return stage == .code
                ? String(localized: "That code isn't right. Check it and try again.")
                : String(localized: "The Apple ID or password is incorrect.")
        case .Auth(let message):
            let detail = message.trimmingCharacters(in: .whitespacesAndNewlines)
            let lead = String(localized: "Apple didn't complete the sign-in.")
            return detail.isEmpty ? lead : "\(lead)\n\(detail)"
        case .Http(let status, _) where status == 429:
            return String(localized: "Apple is limiting sign-in attempts. Wait a few minutes and try again.")
        case .Http:
            return String(localized: "Apple's sign-in service isn't responding. Try again later.")
        case .Network:
            return String(localized: "Couldn't reach Apple. Check your connection and try again.")
        case .SessionExpired:
            return String(localized: "App Store Connect didn't accept the new sign-in. Try again.")
        case .Decode:
            return String(localized: "Apple returned an unexpected response. Try again later.")
        case .Unsupported, .PendingAgreements, .SubmissionNotRemovable, .ReleaseNotFound:
            return stackError.userFacingMessage
        }
    }
}
