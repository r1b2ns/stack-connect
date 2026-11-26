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
    /// that Apple ID, if any. Unless the user chose, "Save password on this
    /// device" follows it: on when a password is saved, off otherwise.
    func emailDidChange()
    /// "Use a different password": back to the password field, without the
    /// saved password (which stays saved until a sign-in replaces it).
    func useDifferentPassword()
    /// "Save password on this device": whether the typed password is kept in
    /// the Keychain once the sign-in finished. Off also removes a password
    /// saved earlier for the Apple ID (once the sign-in finished). The user's
    /// choice wins over the default from then on (see `savesPassword`).
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
    /// "How Your Password Is Used" on the trust panel (flag
    /// `accountConnectionGuide`): presents the explanation sheet.
    func showPasswordUsage()
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
    /// "Save password on this device". Off by default, so a password is never
    /// stored unless the user asks for it (App Review). When a password is
    /// already saved for the Apple ID, the default is on instead, so signing
    /// in never silently removes it. The default follows the Apple ID until
    /// the user toggles it; their choice is then kept (never reset when the
    /// email or the saved-password row changes). Applied only once the
    /// sign-in finished, also when the saved password is used: off then
    /// removes it.
    var savesPassword = false

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

    /// Flag `accountConnectionGuide`: the password screen shows the trust
    /// panel (and its "How Your Password Is Used" link) above the fields,
    /// instead of the single privacy notice under them.
    var showsTrustPanel = false
    /// "How Your Password Is Used" is presented.
    var isShowingPasswordUsage = false

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
    typealias SignInFactory = AppleSessionRenewal.SignInFactory

    static let appleIdWebsite = URL(string: "https://appleid.apple.com")

    @Published var uiState: AppleIdSignInUiState

    private let storage: PersistentStorable
    private let keychain: KeyStorable
    private let renewal: AppleSessionRenewal
    private let passwordStore: ApplePasswordKeychainStore
    private let roleResolver: any AppleSessionRoleResolving
    private let analytics: AnalyticsTracking
    /// The automatic sign-in (`AppleSessionAutoReauthenticator`): its
    /// challenges left at the code step are resumed when signing in again,
    /// an attempt in flight is joined instead of starting a second sign-in,
    /// and none starts while this one is open.
    private let autoReauth: (any AppleSessionManualSignInCoordinating)?

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
    /// `flow` is an automatic sign-in's pending challenge (resumed at the
    /// code step, the password not asked).
    private var resumedChallenge = false
    /// The user toggled "Save password on this device": the default (whether
    /// the Apple ID has a saved password) no longer applies.
    private var savesPasswordExplicitlySet = false
    /// This sign-in holds the automatic sign-in's manual mark
    /// (`beginManualSignIn`) for `heldAppleId`.
    private var heldAppleId: String?
    /// `discard` ran: the screen is gone.
    private var isDiscarded = false

    init(
        mode: AppleIdSignInMode,
        storage: PersistentStorable? = nil,
        keychain: KeyStorable = KeychainStorable.shared,
        sessionStatus: AppleSessionStatusTracking = AppleSessionStatusStore.shared,
        roleResolver: (any AppleSessionRoleResolving)? = nil,
        analytics: AnalyticsTracking = AnalyticsService.shared,
        autoReauth: (any AppleSessionManualSignInCoordinating)? = nil,
        featureFlags: FeatureFlags = .shared,
        makeSignIn: SignInFactory? = nil
    ) {
        var state = AppleIdSignInUiState(mode: mode)
        state.showsTrustPanel = featureFlags.isEnabled(.accountConnectionGuide)
        self.uiState = state
        self.storage = storage ?? SwiftDataStorable.shared
        self.keychain = keychain
        self.renewal = AppleSessionRenewal(keychain: keychain, sessionStatus: sessionStatus, makeSignIn: makeSignIn)
        self.passwordStore = renewal.passwordStore
        self.roleResolver = roleResolver ?? AppleSessionRoleResolver()
        self.analytics = analytics
        self.autoReauth = autoReauth
        updateSavesPasswordDefault()
        if case .signInAgain(let appleId) = mode,
           let challenge = autoReauth?.pendingChallenge(for: appleId) {
            resume(challenge)
        }
    }

    /// Starts at the code screen of an automatic sign-in Apple left waiting
    /// for a code (already sent): the saved password was used, so it isn't
    /// asked. Stale or gone, `submitCode` falls back to a new sign-in.
    private func resume(_ challenge: AppleSessionPendingChallenge) {
        Log.print.info("[AppleIdSignIn] Resuming the automatic sign-in at the code step")
        flow = challenge.flow
        // Saved again (refreshed) once the sign-in finished, as when the
        // saved password is used by hand.
        pendingPassword = passwordStore.password(for: challenge.appleId)
        // The toggle isn't shown at the code step: on, as a password is
        // saved, so it is refreshed rather than removed.
        updateSavesPasswordDefault()
        resumedChallenge = true
        hasStarted = true
        hasTriedSavedPassword = true
        holdManualSignIn()
        uiState.usesSavedPassword = true
        showCode(methods: challenge.methods, phones: challenge.phones, codeLength: challenge.codeLength, delivery: challenge.delivery)
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
        // The toggle is never shown on this path: keep (refresh) the password.
        updateSavesPasswordDefault()
        await performSignIn()
    }

    func emailDidChange() {
        guard uiState.step == .credentials, !uiState.isWorking else { return }
        let id = appleId
        uiState.usesSavedPassword = !id.isEmpty
            && !declinedSavedPassword.contains(id)
            && passwordStore.hasPassword(for: id)
        updateSavesPasswordDefault()
    }

    /// Unless the user toggled it, "Save password on this device" is on only
    /// when a password is already saved for the Apple ID (also after "Use a
    /// different password", so the saved one is replaced, not removed).
    private func updateSavesPasswordDefault() {
        guard !savesPasswordExplicitlySet else { return }
        let id = appleId
        uiState.savesPassword = !id.isEmpty && passwordStore.hasPassword(for: id)
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
        guard uiState.step == .credentials, !uiState.isWorking else { return }
        // Even a value equal to the default is a choice: it stops following
        // the Apple ID. Only a change is tracked.
        savesPasswordExplicitlySet = true
        guard uiState.savesPassword != savesPassword else { return }
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
        // The automatic sign-in is already signing in with this password:
        // wait for it rather than run a second sign-in (and a second code).
        if usesSavedPassword, await joinAutomaticSignIn() { return }
        holdManualSignIn()

        analytics.track(.action(.appleIdSignInStarted, on: .appleIdSignIn, parameters: modeParameters))
        hasStarted = true
        uiState.errorMessage = nil
        uiState.notice = nil
        uiState.isWorking = true
        defer { uiState.isWorking = false }

        do {
            let flow = try renewal.makeFlow(reusingSessionOf: savedSessionAppleId)
            self.flow = flow
            pendingPassword = password
            let step = try await flow.start(email: email, password: password)
            await handle(step)
        } catch {
            endFlow()
            let kind = AppleSessionRenewal.failureKind(of: error)
            if usesSavedPassword, kind == .wrongPassword {
                savedPasswordRefused(appleId: email)
                trackSignIn(.failure, failure: .invalidCredentials)
            } else {
                if usesSavedPassword {
                    // Only a refused password removes it: after a 429, a 5xx,
                    // a network failure or anything else the saved password
                    // stays in use, so a retry doesn't ask for it.
                    uiState.usesSavedPassword = true
                    if kind == .transient {
                        Log.print.notice("[AppleIdSignIn] Apple or the network couldn't answer: kept the saved password for the retry")
                    }
                }
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
        AppleSessionRenewal.isWrongPassword(error)
    }

    // MARK: - Automatic sign-in in flight

    /// Signing in again while the automatic sign-in runs for the Apple ID:
    /// shows it working, waits for it and applies its outcome. Never starts
    /// a sign-in of its own.
    /// - Returns: whether an automatic attempt was joined (its outcome is
    ///   applied; the caller stops).
    private func joinAutomaticSignIn() async -> Bool {
        guard case .signInAgain = uiState.mode, let autoReauth, autoReauth.isAttemptInFlight(for: appleId) else { return false }
        let id = appleId
        Log.print.info("[AppleIdSignIn] The automatic sign-in is running: waiting for it instead of signing in again")
        uiState.isWorking = true
        uiState.errorMessage = nil
        uiState.notice = String(localized: "Reconnecting Apple ID \(id)…",
                                comment: "Home tip while the app signs in again on its own, with the saved password, to an expired Apple ID. The placeholder is the Apple ID (an e-mail).")
        let outcome = await autoReauth.inFlightOutcome(for: id)
        uiState.isWorking = false
        uiState.notice = nil
        // The screen was closed meanwhile: nothing to show.
        guard !hasConcluded, !isDiscarded else { return true }
        guard let outcome else { return false }

        switch outcome {
        case .done:
            Log.print.info("[AppleIdSignIn] The automatic sign-in renewed the session")
            conclude()
        case .needsCode:
            if let challenge = autoReauth.pendingChallenge(for: id) {
                resume(challenge)
            } else {
                // Gone already (stale): the saved password signs in on a tap.
                uiState.usesSavedPassword = passwordStore.hasPassword(for: id)
            }
        case .failed:
            // The saved password is kept and stays in use: a tap retries.
            uiState.usesSavedPassword = passwordStore.hasPassword(for: id)
            if let error = autoReauth.lastFailure(for: id) {
                uiState.errorMessage = Self.message(for: error, stage: .password)
            } else {
                uiState.errorMessage = String(localized: "Apple didn't complete the sign-in.")
            }
        case .invalidCredentials:
            // The automatic sign-in removed the refused password already.
            savedPasswordRefused(appleId: id)
        }
        return true
    }

    /// Keeps the automatic sign-in away while this one runs (signing in
    /// again only). Released by `endFlow` and `discard`.
    private func holdManualSignIn() {
        guard case .signInAgain = uiState.mode, let autoReauth else { return }
        let id = appleId
        guard heldAppleId != id else { return }
        releaseManualSignIn()
        autoReauth.beginManualSignIn(for: id)
        heldAppleId = id
    }

    private func releaseManualSignIn() {
        guard let id = heldAppleId else { return }
        heldAppleId = nil
        autoReauth?.endManualSignIn(for: id)
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
            // A transient failure (network, 429, 5xx) says nothing about the
            // challenge: show it and keep the code step; anything else means
            // the challenge went stale.
            if resumedChallenge, !AppleSessionRenewal.isTransient(error) {
                await restartAfterStaleChallenge(error)
                return
            }
            fail(error, message: Self.message(for: error, stage: .code))
        }
    }

    /// The resumed challenge no longer works (it expired with its code): sign
    /// in again with the saved password, which sends a new code; without one,
    /// back to the password field.
    private func restartAfterStaleChallenge(_ error: Error) async {
        Log.print.notice("[AppleIdSignIn] The resumed sign-in was refused (\(error.localizedDescription, privacy: .public)): signing in again")
        resetToCredentials()
        uiState.isWorking = false
        hasTriedSavedPassword = false
        await signInWithSavedPasswordIfAvailable()
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
        if resumedChallenge {
            // The user left the automatic sign-in's code: it can't be resumed.
            resumedChallenge = false
            autoReauth?.discardPendingChallenge(for: appleId)
        }
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

    func showPasswordUsage() {
        guard uiState.showsTrustPanel, !uiState.isShowingPasswordUsage else { return }
        analytics.track(.buttonTap(.howPasswordIsUsed, on: .appleIdSignIn))
        uiState.isShowingPasswordUsage = true
    }

    func discard() {
        // Whatever happened, a closed screen no longer keeps the automatic
        // sign-in away.
        isDiscarded = true
        releaseManualSignIn()
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
            autoReauth?.discardPendingChallenge(for: appleId)
            resumedChallenge = false
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
            try await renewal.storeSession(
                of: flow,
                appleId: appleId,
                password: pendingPassword,
                savesPassword: uiState.savesPassword
            )
            endFlow()
            return true
        } catch {
            Log.print.error("[AppleIdSignIn] Finishing the sign-in failed: \(error.localizedDescription, privacy: .public)")
            uiState.errorMessage = Self.message(for: error, stage: .password)
            return false
        }
    }

    /// Drops the core's sign-in and the password kept for it.
    private func endFlow() {
        flow = nil
        pendingPassword = nil
        releaseManualSignIn()
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

    /// Signing in again reuses the Apple ID's saved session (its trust
    /// cookie can spare the code); Add Account starts fresh.
    private var savedSessionAppleId: String? {
        guard case .signInAgain = uiState.mode else { return nil }
        return appleId
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
        if OfflineError.isConnectivityFailure(error) || AppleSessionRenewal.isConnectivityURLError(error) {
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
