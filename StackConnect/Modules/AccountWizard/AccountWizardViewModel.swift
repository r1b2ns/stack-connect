import Combine
import Foundation
import StackProtocols

// MARK: - Protocol

@MainActor
protocol AccountWizardViewModelProtocol: ObservableObject {
    associatedtype Connection: AddAccountViewModelProtocol
    associatedtype AppleSignIn: AppleIdSignInViewModelProtocol

    var uiState: AccountWizardUiState { get set }
    /// The key file / Google sign-in engine of the chosen store (API key,
    /// service account, Google account), once on its Credentials step.
    var connection: Connection? { get }
    /// The email and password sign-in (App Store Connect), once on its
    /// Credentials step.
    var appleSignIn: AppleSignIn? { get }

    /// The bottom button of the current step, `nil` when the step has none
    /// (Type: a row tap goes on).
    var primaryTitle: String? { get }
    var canContinue: Bool { get }
    var canGoBack: Bool { get }

    /// Type step: picks the kind and goes on.
    func chooseKind(_ kind: AccountWizardKind)
    /// Method step: picks the method and goes on.
    func chooseMethod(_ method: AccountWizardMethod)
    /// The bottom button: Continue, Continue with Google, Verify, Connect,
    /// Import or Sign In Again, depending on the step and method.
    func primaryAction() async
    func goBack()

    /// The Credentials step appeared: the connection guide opens on its own
    /// before the first connection (flag `accountConnectionGuide`).
    func credentialsStepDidAppear()
    /// "How It Works": the connection guide again.
    func showConnectionGuide()
    func dismissConnectionGuide()

    /// Import: the `.scexport` file picked.
    func selectImportFile(_ url: URL)

    /// Done screen: "Add Another Account", back to the Type step.
    func addAnotherAccount()
    /// The wizard is going away: an unfinished sign-in is dropped.
    func discard() async
}

// MARK: - UiState

/// The connection guide over the wizard (flag `accountConnectionGuide`).
enum AccountWizardGuide: String, Identifiable, Equatable {
    /// On its own, before the first connection: Skip / Continue go on to the
    /// credentials, Cancel closes the wizard.
    case firstConnection
    /// From "How It Works": Done closes it.
    case reopened

    var id: String { rawValue }
}

/// The `.scexport` file of an import.
struct AccountWizardImportState: Equatable {
    var fileURL: URL?
    /// Shown on the file row; never the content.
    var fileName: String?
    /// The password the file was encrypted with. Cleared once imported.
    var password = ""
    /// The account name read from the file, once it could be decrypted.
    var fileAccountName: String?
    /// The name to import it under (Review).
    var accountName = ""

    var canDecrypt: Bool { fileURL != nil && !password.isEmpty }
    var isDecrypted: Bool { fileAccountName != nil }
}

/// What the done screen says.
struct AccountWizardResult: Equatable {
    /// The store of the accounts, `nil` when unknown.
    let provider: ProviderType?
    /// The accounts added (or the one reconnected).
    let names: [String]
    let isReconnect: Bool
}

struct AccountWizardUiState {
    var config: AccountWizardConfig
    /// The kind chosen on Type, or named by the entry.
    var kind: AccountWizardKindConfig?
    /// The method chosen on Method, or the kind's only one.
    var method: AccountWizardMethod?
    var step: AccountWizardStep
    var isWorking = false
    /// A failure of the wizard itself (import, reconnect). The connection
    /// engines show their own errors.
    var errorMessage: String?
    var result: AccountWizardResult?
    var importFile = AccountWizardImportState()
    /// Flag `accountConnectionGuide`: the guide and "How It Works".
    var isConnectionGuideEnabled = false
    var guide: AccountWizardGuide?

    init(config: AccountWizardConfig) {
        self.config = config
        self.kind = config.initialKind
        self.method = config.initialMethod
        self.step = Self.firstStep(for: config)
    }

    static func firstStep(for config: AccountWizardConfig) -> AccountWizardStep {
        AccountWizardFlow.steps(entry: config.entry, kind: config.initialKind, method: config.initialMethod).first ?? .credentials
    }

    var entry: AccountWizardEntry { config.entry }

    var reconnectAccount: AccountModel? {
        if case .reconnect(let account) = config.entry { return account }
        return nil
    }

    var steps: [AccountWizardStep] {
        AccountWizardFlow.steps(entry: config.entry, kind: kind, method: method)
    }

    var stepIndex: Int { steps.firstIndex(of: step) ?? 0 }

    /// The Type step of a `.chooseKind` entry. Back to it, the kind chosen
    /// before is kept (choosing it again keeps what was typed), but nothing
    /// is chosen yet as far as the header goes: neutral tint, shortest path.
    var isChoosingKind: Bool { entry == .chooseKind && step == .type }

    /// The number of steps the header shows. `steps` still drives moving on.
    var stepCount: Int {
        isChoosingKind
            ? AccountWizardFlow.steps(entry: entry, kind: nil, method: nil).count
            : steps.count
    }

    /// The store whose color tints the wizard: none while choosing the kind.
    var tintProvider: ProviderType? {
        isChoosingKind ? nil : provider
    }

    /// 0...1, the current step included.
    var progress: Double {
        guard stepCount > 0 else { return 0 }
        return Double(stepIndex + 1) / Double(stepCount)
    }

    var isFinished: Bool { result != nil }

    /// The store being connected (the import's store is read from its file).
    var provider: ProviderType? {
        reconnectAccount?.providerType ?? kind?.kind.provider
    }
}

// MARK: - Implementation

/// The one account wizard (plan `unified-accounts.md` §3): every entry point
/// opens it with an `AccountWizardConfig`, and only that config changes.
///
/// It owns the step engine and reuses the existing connection logic behind
/// one Credentials component per `AuthStyle`:
/// - `.configFile`: `AddAccountViewModel` (API key, service account JSON:
///   validated and saved as before) or `AccountImporter` (`.scexport`);
/// - `.credentials`: `AppleIdSignInViewModel` (email, password, two-factor
///   code, teams; signing in again for a reconnect);
/// - `.webSignIn`: `AddAccountViewModel`'s Google sign-in, or
///   `GoogleAccessRecovery` for a reconnect.
@MainActor
final class AccountWizardViewModel: AccountWizardViewModelProtocol {

    typealias ConnectionFactory = @MainActor (ProviderType, AddAccountCredentialMode) -> AddAccountViewModel
    typealias AppleSignInFactory = @MainActor (AppleIdSignInMode) -> AppleIdSignInViewModel
    /// Decrypts a `.scexport` file. - Returns: the account name it holds.
    typealias ImportPreviewer = (URL, String) throws -> String

    @Published var uiState: AccountWizardUiState
    @Published private(set) var connection: AddAccountViewModel?
    @Published private(set) var appleSignIn: AppleIdSignInViewModel?

    private let storage: PersistentStorable
    private let keychain: KeyStorable
    private let analytics: AnalyticsTracking
    private let googleAuth: any GoogleAuthServicing
    private let connectionGuide: any ConnectionGuideStoring
    private let makeConnection: ConnectionFactory
    private let makeAppleSignIn: AppleSignInFactory
    private let previewImport: ImportPreviewer
    private let importer: AccountImporter
    private let requestSync: () -> Void

    /// The engines already created, per method, so Back keeps what was typed.
    private var connections: [AccountWizardMethod: AddAccountViewModel] = [:]
    private var connectionCancellables = Set<AnyCancellable>()
    private var appleCancellables = Set<AnyCancellable>()

    init(
        entry: AccountWizardEntry,
        storage: PersistentStorable? = nil,
        keychain: KeyStorable = KeychainStorable.shared,
        analytics: AnalyticsTracking = AnalyticsService.shared,
        featureFlags: FeatureFlags = .shared,
        googleAuth: (any GoogleAuthServicing)? = nil,
        connectionGuide: any ConnectionGuideStoring = ConnectionGuideStore(),
        makeConnection: ConnectionFactory? = nil,
        makeAppleSignIn: AppleSignInFactory? = nil,
        previewImport: ImportPreviewer? = nil,
        requestSync: (() -> Void)? = nil
    ) {
        let storage: PersistentStorable = storage ?? SwiftDataStorable.shared
        let googleAuth = googleAuth ?? GoogleAuthService.shared
        let config = AccountWizardConfig.make(
            entry: entry,
            featureFlags: featureFlags,
            isGoogleSignInConfigured: googleAuth.isConfigured
        )
        var state = AccountWizardUiState(config: config)
        state.isConnectionGuideEnabled = featureFlags.isEnabled(.accountConnectionGuide)
        self.uiState = state
        self.storage = storage
        self.keychain = keychain
        self.analytics = analytics
        self.googleAuth = googleAuth
        self.connectionGuide = connectionGuide
        self.importer = AccountImporter(storage: storage, keychain: keychain, featureFlags: featureFlags)
        self.makeConnection = makeConnection ?? { provider, mode in
            AddAccountViewModel(
                providerType: provider,
                storage: storage,
                keychain: keychain,
                analytics: analytics,
                featureFlags: featureFlags,
                googleAuth: googleAuth,
                credentialMode: mode
            )
        }
        self.makeAppleSignIn = makeAppleSignIn ?? { mode in
            // Signing in again resumes the code step an automatic sign-in left.
            AppleIdSignInViewModel(
                mode: mode,
                storage: storage,
                keychain: keychain,
                analytics: analytics,
                autoReauth: AppleSessionAutoReauthenticator.shared,
                featureFlags: featureFlags
            )
        }
        self.previewImport = previewImport ?? Self.previewImportFile
        self.requestSync = requestSync ?? { _ = SyncService.shared.syncAll(trigger: .foreground, screen: nil) }

        Log.print.info("[AccountWizard] Opened: \(entry.id, privacy: .public)")
        if uiState.step == .credentials { prepareCredentials() }
    }

    // MARK: - Bottom button

    var primaryTitle: String? {
        guard !uiState.isFinished else { return nil }
        switch uiState.step {
        case .type, .method:
            // A row tap goes on.
            return nil
        case .items:
            return String(localized: "Continue")
        case .code:
            return String(localized: "Verify")
        case .credentials:
            return credentialsPrimaryTitle
        case .review:
            return uiState.kind?.kind == .importFile
                ? String(localized: "Import Account", comment: "Account wizard: last button of an import.")
                : String(localized: "Connect Account", comment: "Account wizard: last button, adds the account(s).")
        }
    }

    private var credentialsPrimaryTitle: String {
        let isReconnect = uiState.entry.isReconnect
        switch uiState.method {
        case .googleSignIn?:
            if isReconnect { return String(localized: "Sign In Again", comment: "Account wizard: reconnects a Google account on Google's page.") }
            return connection?.uiState.google.step == .picking
                ? String(localized: "Continue")
                : String(localized: "Continue with Google", comment: "Account wizard: opens Google's sign-in page.")
        case .scexportFile?:
            return isReconnect
                ? String(localized: "Import Again", comment: "Account wizard: re-imports the file of an expired shared account.")
                : String(localized: "Continue")
        default:
            return String(localized: "Continue")
        }
    }

    var canContinue: Bool {
        guard !uiState.isWorking, !uiState.isFinished else { return false }
        switch uiState.step {
        case .type:
            return false
        case .method:
            return uiState.method != nil
        case .credentials:
            return canContinueFromCredentials
        case .code:
            return appleSignIn?.uiState.canSubmitCode ?? false
        case .items:
            return canContinueFromItems
        case .review:
            return canConnect
        }
    }

    private var canContinueFromCredentials: Bool {
        switch uiState.method {
        case .apiKey?, .serviceAccount?:
            guard let connection else { return false }
            return !connection.uiState.isBusy && connection.uiState.hasKeyFileCredentials
        case .googleSignIn?:
            if uiState.entry.isReconnect { return true }
            guard let connection else { return false }
            return !connection.uiState.isBusy
        case .appleIdSignIn?:
            return appleSignIn?.uiState.canSignIn ?? false
        case .scexportFile?:
            return uiState.importFile.canDecrypt
        case nil:
            return false
        }
    }

    private var canContinueFromItems: Bool {
        switch uiState.method {
        case .appleIdSignIn?:
            return appleSignIn?.uiState.canSave ?? false
        case .googleSignIn?:
            guard let google = connection?.uiState.google else { return false }
            return google.step == .picking && !google.selectedIds.isEmpty
        default:
            return false
        }
    }

    private var canConnect: Bool {
        switch uiState.method {
        case .apiKey?, .serviceAccount?, .googleSignIn?:
            guard let connection else { return false }
            return connection.uiState.canSave && !connection.uiState.isBusy
        case .appleIdSignIn?:
            guard let apple = appleSignIn?.uiState else { return false }
            return apple.canSave
        case .scexportFile?:
            return uiState.importFile.isDecrypted
                && !uiState.importFile.accountName.trimmingCharacters(in: .whitespaces).isEmpty
        case nil:
            return false
        }
    }

    var canGoBack: Bool {
        guard !uiState.isWorking, !uiState.isFinished, uiState.stepIndex > 0 else { return false }
        if uiState.step == .code, appleSignIn?.uiState.isWorking == true { return false }
        return true
    }

    // MARK: - Type and Method

    func chooseKind(_ kind: AccountWizardKind) {
        guard uiState.step == .type, let config = uiState.config.kindConfig(for: kind) else { return }
        analytics.track(.buttonTap(Self.kindButton(for: kind), on: .accountWizardType))
        if uiState.kind?.kind != kind {
            // Another store: nothing typed for the previous one carries over.
            resetEngines()
            uiState.importFile = AccountWizardImportState()
            uiState.method = config.defaultMethod
        }
        uiState.kind = config
        uiState.errorMessage = nil
        advance()
    }

    func chooseMethod(_ method: AccountWizardMethod) {
        guard uiState.step == .method, uiState.kind?.methods.contains(method) == true else { return }
        if let connectionMethod = method.connectionMethod {
            analytics.track(.buttonTap(.connectionMethodButton(for: connectionMethod), on: .accountWizardMethod))
        }
        uiState.method = method
        uiState.errorMessage = nil
        advance()
    }

    // MARK: - Moving

    func primaryAction() async {
        guard canContinue else { return }
        analytics.track(.buttonTap(.continue, on: uiState.step.analyticsScreen))
        uiState.errorMessage = nil
        switch uiState.step {
        case .type:
            return
        case .method, .items:
            advance()
        case .credentials:
            await continueFromCredentials()
        case .code:
            await appleSignIn?.submitCode()
        case .review:
            await connect()
        }
    }

    func goBack() {
        guard canGoBack else { return }
        analytics.track(.buttonTap(.back, on: uiState.step.analyticsScreen))
        uiState.errorMessage = nil
        let steps = uiState.steps
        let index = uiState.stepIndex
        let current = uiState.step
        let previous = steps[index - 1]

        if uiState.method == .appleIdSignIn {
            switch current {
            case .code:
                // The code belongs to this attempt: start the sign-in over.
                appleSignIn?.startOver()
            case .items:
                // Signed in already: going back means signing in again.
                replaceAppleSignIn()
                uiState.step = .credentials
                return
            default:
                break
            }
        }
        uiState.step = previous
        if previous == .credentials { prepareCredentials() }
    }

    /// The next step of the template (the engine), if any.
    private func advance() {
        let steps = uiState.steps
        guard let index = steps.firstIndex(of: uiState.step), index + 1 < steps.count else { return }
        uiState.step = steps[index + 1]
        if uiState.step == .credentials { prepareCredentials() }
    }

    private func move(to step: AccountWizardStep) {
        guard uiState.steps.contains(step) else { return }
        uiState.step = step
    }

    // MARK: - Credentials

    /// Creates the engine of the chosen method, the first time.
    private func prepareCredentials() {
        guard let method = uiState.method else { return }
        switch method {
        case .apiKey, .serviceAccount, .googleSignIn:
            guard !uiState.entry.isReconnect, let provider = uiState.kind?.kind.provider else {
                connection = nil
                return
            }
            if let existing = connections[method] {
                connection = existing
            } else {
                let engine = makeConnection(provider, method == .googleSignIn ? .googleSignIn : .keyFile)
                connections[method] = engine
                connection = engine
            }
            observe(connection)
        case .appleIdSignIn:
            if appleSignIn == nil { replaceAppleSignIn() }
        case .scexportFile:
            break
        }
    }

    private func replaceAppleSignIn() {
        appleSignIn?.discard()
        let mode: AppleIdSignInMode
        if let account = uiState.reconnectAccount {
            if let appleId = AppleSessionReferences.reference(of: account, keychain: keychain)?.appleId, !appleId.isEmpty {
                mode = .signInAgain(appleId: appleId)
            } else {
                // Its session reference is gone: the Apple ID is typed
                // (prefilled when unambiguous) and the reference restored.
                Log.print.notice("[AccountWizard] The reconnected account has no Apple ID session reference: asking for the Apple ID")
                mode = .reconnectAccount(accountId: account.id, accountName: account.name)
            }
        } else {
            mode = .addAccounts
        }
        let signIn = makeAppleSignIn(mode)
        appleSignIn = signIn
        appleCancellables.removeAll()
        signIn.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &appleCancellables)
        signIn.$uiState
            .map(\.step)
            .removeDuplicates()
            .sink { [weak self] step in self?.appleStepChanged(step) }
            .store(in: &appleCancellables)
    }

    private func observe(_ engine: AddAccountViewModel?) {
        connectionCancellables.removeAll()
        guard let engine else { return }
        engine.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &connectionCancellables)
        engine.$uiState
            .map(\.google.step)
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] step in self?.googleStepChanged(step) }
            .store(in: &connectionCancellables)
    }

    /// The Apple ID sign-in moved on its own (a typed code is submitted as
    /// soon as it is complete, a saved password signs in on appear).
    private func appleStepChanged(_ step: AppleIdSignInUiState.Step) {
        guard uiState.method == .appleIdSignIn, !uiState.isFinished else { return }
        switch step {
        case .credentials, .needsAcknowledgement:
            if uiState.step == .code { uiState.step = .credentials }
        case .code:
            if uiState.step == .credentials { move(to: .code) }
        case .teams:
            if uiState.step == .credentials || uiState.step == .code { move(to: .items) }
        case .finished:
            finish()
        }
    }

    /// Google listed what the login can add: on to the Items step.
    private func googleStepChanged(_ step: GoogleSignInState.Step) {
        guard uiState.method == .googleSignIn, uiState.step == .credentials, step == .picking else { return }
        move(to: .items)
    }

    func credentialsStepDidAppear() {
        guard uiState.step == .credentials, uiState.isConnectionGuideEnabled, !uiState.entry.isReconnect,
              uiState.provider != nil, uiState.kind?.kind != .importFile,
              !connectionGuide.hasShownGuide else { return }
        connectionGuide.markGuideShown()
        uiState.guide = .firstConnection
    }

    func showConnectionGuide() {
        guard uiState.isConnectionGuideEnabled, uiState.guide == nil, uiState.provider != nil else { return }
        analytics.track(.buttonTap(.howItWorks, on: uiState.step.analyticsScreen))
        uiState.guide = .reopened
    }

    func dismissConnectionGuide() {
        uiState.guide = nil
    }

    /// The methods the guide describes: the chosen kind's store methods.
    var guideMethods: [AccountConnectionMethod] {
        uiState.kind?.methods.compactMap(\.connectionMethod) ?? []
    }

    private func continueFromCredentials() async {
        switch uiState.method {
        case .apiKey?, .serviceAccount?:
            advance()
        case .googleSignIn?:
            if let account = uiState.reconnectAccount {
                await reconnectGoogle(account)
            } else if connection?.uiState.google.step == .picking {
                advance()
            } else {
                await connection?.signInWithGoogle()
            }
        case .appleIdSignIn?:
            await appleSignIn?.signIn()
        case .scexportFile?:
            await decryptImportFile()
        case nil:
            return
        }
    }

    // MARK: - Import

    func selectImportFile(_ url: URL) {
        guard uiState.method == .scexportFile else { return }
        analytics.track(.buttonTap(.importFile, on: .accountWizardCredentials))
        uiState.importFile.fileURL = url
        uiState.importFile.fileName = url.lastPathComponent
        uiState.importFile.fileAccountName = nil
        uiState.errorMessage = nil
    }

    private func decryptImportFile() async {
        guard let url = uiState.importFile.fileURL else { return }
        analytics.track(.buttonTap(.decrypt, on: .accountWizardCredentials))
        do {
            let name = try previewImport(url, uiState.importFile.password)
            uiState.importFile.fileAccountName = name
            if uiState.importFile.accountName.trimmingCharacters(in: .whitespaces).isEmpty {
                uiState.importFile.accountName = name
            }
        } catch {
            uiState.errorMessage = error.userFacingMessage
            Log.print.notice("[AccountWizard] The import file couldn't be decrypted")
            return
        }
        if let account = uiState.reconnectAccount {
            // Re-import in place: same id, same name, offline data kept.
            await performImport(customName: account.name, replacing: account)
        } else {
            advance()
        }
    }

    private func performImport(customName: String, replacing account: AccountModel?) async {
        guard let url = uiState.importFile.fileURL else { return }
        analytics.track(.buttonTap(.confirmImport, on: uiState.step.analyticsScreen))
        uiState.isWorking = true
        defer { uiState.isWorking = false }
        let options = AccountImporter.Options(
            expectedProvider: account?.providerType,
            replacingAccountId: account?.id
        )
        let outcome = await importer.importAccount(
            from: url,
            password: uiState.importFile.password,
            customName: customName,
            options: options
        )
        let action: AnalyticsAction = account == nil ? .importAccount : .reimportAccount
        switch outcome {
        case .success(let imported):
            analytics.track(.action(action, on: uiState.step.analyticsScreen, result: .success))
            Log.print.info("[AccountWizard] \(account == nil ? "Imported" : "Re-imported", privacy: .public) a \(imported.providerType.rawValue, privacy: .public) account")
            uiState.importFile.password = ""
            uiState.result = AccountWizardResult(provider: imported.providerType, names: [imported.name], isReconnect: account != nil)
        case .failure(let error):
            analytics.track(.action(action, on: uiState.step.analyticsScreen, result: .failure,
                                    parameters: AnalyticsErrorCategory(importReason: error.reason).parameters))
            uiState.errorMessage = error.message
        }
    }

    /// Reads the account name of a `.scexport` file (the file is decrypted
    /// again when imported, as the import sheets always did).
    static func previewImportFile(url: URL, password: String) throws -> String {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else {
            throw AccountWizardError(message: String(localized: "Failed to read file."))
        }
        let json = try AccountCrypto.decrypt(data: data, password: password)
        guard let jsonData = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            throw AccountWizardError(message: String(localized: "Invalid JSON format."))
        }
        return (dict["name"] as? String) ?? ""
    }

    // MARK: - Reconnect

    private func reconnectGoogle(_ account: AccountModel) async {
        let recovery = GoogleAccessRecovery(
            loginId: GoogleLoginReferences.loginId(of: account, keychain: keychain),
            providerType: account.providerType,
            auth: googleAuth,
            analytics: analytics,
            screen: .accountWizardCredentials
        )
        let prompt = GoogleAccessPrompt(
            reason: .signInRequired,
            email: GoogleLoginReferences.email(of: account, keychain: keychain)
        )
        uiState.isWorking = true
        let resolved = await recovery.resolve(prompt) { [weak self] update in
            self?.uiState.errorMessage = update.feedback
        }
        uiState.isWorking = false
        guard resolved else {
            if recovery.loginId == nil {
                uiState.errorMessage = String(localized: "This account's Google sign-in isn't on this device anymore. Remove the account and add it again.",
                                              comment: "Account wizard: reconnecting a Google account whose login is gone.")
            }
            return
        }
        finish()
    }

    // MARK: - Review

    private func connect() async {
        switch uiState.method {
        case .apiKey?, .serviceAccount?, .googleSignIn?:
            guard let connection else { return }
            let names = pendingConnectionNames(connection.uiState)
            await connection.save()
            if connection.uiState.isSaved {
                uiState.result = AccountWizardResult(provider: connection.uiState.providerType, names: names, isReconnect: false)
            }
        case .appleIdSignIn?:
            await appleSignIn?.save()
        case .scexportFile?:
            await performImport(customName: uiState.importFile.accountName, replacing: nil)
        case nil:
            return
        }
    }

    /// The names of the accounts a save adds: one per Firebase project
    /// picked after a Google sign-in, the typed name otherwise.
    private func pendingConnectionNames(_ state: AddAccountUiState) -> [String] {
        if state.isGoogleSignInMode, state.providerType == .firebase {
            return state.google.selectableItems
                .filter { state.google.selectedIds.contains($0.id) }
                .map(\.resource.title)
        }
        return [state.accountName.trimmingCharacters(in: .whitespaces)]
    }

    /// The Apple ID sign-in finished (accounts added) or a reconnect worked.
    private func finish() {
        guard !uiState.isFinished else { return }
        if let account = uiState.reconnectAccount {
            Log.print.info("[AccountWizard] Reconnected a \(account.providerType.rawValue, privacy: .public) account")
            uiState.result = AccountWizardResult(provider: account.providerType, names: [account.name], isReconnect: true)
            requestSync()
            return
        }
        let teams = appleSignIn?.uiState.selectableTeams
            .filter { appleSignIn?.uiState.selectedTeamIds.contains($0.id) == true }
            .map(\.team.name) ?? []
        uiState.result = AccountWizardResult(provider: .apple, names: teams, isReconnect: false)
    }

    // MARK: - Done and closing

    func addAnotherAccount() {
        guard uiState.isFinished else { return }
        analytics.track(.buttonTap(.addAnotherAccount, on: .accountWizardDone))
        resetEngines()
        let config = AccountWizardConfig(entry: .chooseKind, kinds: uiState.config.kinds)
        var state = AccountWizardUiState(config: config)
        state.isConnectionGuideEnabled = uiState.isConnectionGuideEnabled
        uiState = state
    }

    func discard() async {
        for engine in connections.values {
            await engine.discardUnsavedGoogleLogin()
        }
        appleSignIn?.discard()
        if !uiState.isFinished {
            Log.print.info("[AccountWizard] Closed before the end")
        }
    }

    private func resetEngines() {
        connectionCancellables.removeAll()
        appleCancellables.removeAll()
        let engines = Array(connections.values)
        connections = [:]
        connection = nil
        appleSignIn?.discard()
        appleSignIn = nil
        // A Google login signed in for a store left behind is signed out.
        Task {
            for engine in engines { await engine.discardUnsavedGoogleLogin() }
        }
    }

    // MARK: - Analytics

    private static func kindButton(for kind: AccountWizardKind) -> AnalyticsButton {
        switch kind {
        case .provider(let provider): return .providerButton(for: provider)
        case .importFile:             return .importAccount
        }
    }
}

// MARK: - Error

/// A wizard failure with its user-facing message.
struct AccountWizardError: LocalizedError, Equatable {
    let message: String
    var errorDescription: String? { message }
}

// MARK: - Analytics screens

extension AccountWizardStep {
    var analyticsScreen: AnalyticsScreen {
        switch self {
        case .type:        return .accountWizardType
        case .method:      return .accountWizardMethod
        case .credentials: return .accountWizardCredentials
        case .code:        return .accountWizardCode
        case .items:       return .accountWizardItems
        case .review:      return .accountWizardReview
        }
    }
}
