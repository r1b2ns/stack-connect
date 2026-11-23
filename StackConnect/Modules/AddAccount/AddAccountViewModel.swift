import Foundation
import StackProtocols
import APIProviderFirebase

// MARK: - Protocol

@MainActor
protocol AddAccountViewModelProtocol: ObservableObject {
    var uiState: AddAccountUiState { get set }
    func save() async

    // MARK: Sign in with Google (Google Play and Firebase, plan Phase 2)

    /// Switches between "Sign in with Google" and the service account JSON form.
    func setCredentialMode(_ mode: AddAccountCredentialMode)
    /// Opens Google's sign-in page, then lists what the login can add.
    func signInWithGoogle() async
    /// Asks Google again for the scopes the user left unticked (incremental).
    func grantMissingGoogleAccess() async
    func toggleGoogleItem(_ id: String)
    func setAllGoogleItemsSelected(_ selected: Bool)
    /// Add Account closed without saving: a login signed in here that no
    /// account uses is signed out, so no orphan grant stays on the device.
    func discardUnsavedGoogleLogin() async

    // MARK: Sign in with Apple ID (App Store Connect, plan apple-id-sign-in.md)

    /// Opens the "Sign in with Apple ID" screens (flag `appleIdSignIn`).
    func openAppleIdSignIn()

    // MARK: Connection guide and method chooser (flag `accountConnectionGuide`)

    /// The guide shown on its own (`root == .connectionGuide`) appeared: it is
    /// recorded, so it never opens on its own again.
    func connectionGuideDidAppear()
    /// "Skip" or "Continue" on the guide shown on its own: on to the method
    /// chooser, or straight to the form when there is a single method.
    func finishConnectionGuide()
    /// "How It Works" (chooser or form): reopens the guide over Add Account.
    func showConnectionGuide()
    /// A method card of the chooser: pushes that method's form (or the
    /// email and password screens).
    func chooseMethod(_ method: AccountConnectionMethod)
}

/// The first screen of Add Account.
enum AddAccountRoot: Equatable {
    /// The connection guide, before the first account connection (flag ON).
    case connectionGuide
    /// The method chooser (flag ON, two or more methods available).
    case methods
    /// The form: as before the flag (flag OFF), or the single method's form.
    case form
}

// MARK: - UiState

struct AddAccountUiState {
    var accountName = ""
    var issuerID = ""
    var privateKeyID = ""
    var privateKey = ""
    var firebaseJSON = ""
    var googlePlayJSON = ""
    /// Optional Play Console developer account ID (plan U3): digits, or a
    /// pasted Play Console URL. Empty ⇒ the Users tab asks for it later.
    var googlePlayDeveloperId = ""
    var isValidating = false
    var validationError: String?
    var isSaved = false
    var providerType: ProviderType
    var role: AccountRole = .unspecified

    /// Whether "Sign in with Google" is offered (flag `googleSignIn`, a Play or
    /// Firebase account, a build with an OAuth client ID).
    var isGoogleSignInAvailable = false
    var credentialMode: AddAccountCredentialMode = .keyFile
    var google = GoogleSignInState()

    /// Whether "Sign in with Apple ID" is offered next to the API key form
    /// (flag `appleIdSignIn`, an App Store Connect account).
    var isAppleIdSignInAvailable = false
    /// The Apple ID sign-in screens are pushed.
    var isShowingAppleIdSignIn = false

    /// Flag `accountConnectionGuide`: the connection guide, the method chooser
    /// and the "How It Works" entry. OFF: Add Account exactly as before.
    var isConnectionGuideEnabled = false
    /// The ways to connect `providerType` this build offers, in display order.
    var availableMethods: [AccountConnectionMethod] = []
    /// Where Add Account starts (`.form` whenever the flag is OFF).
    var root: AddAccountRoot = .form
    /// The method picked on the chooser (its form's title).
    var chosenMethod: AccountConnectionMethod?
    /// The form of the method picked on the chooser is pushed.
    var isShowingMethodForm = false
    /// The guide reopened from "How It Works" is presented.
    var isShowingConnectionGuide = false

    var isGoogleSignInMode: Bool {
        isGoogleSignInAvailable && credentialMode == .googleSignIn
    }

    /// The chooser offers the methods (flag ON, more than one method), so
    /// the forms leave out their own switch to the other method ("Sign in
    /// with Google instead", "No API Key?", "Use a service account JSON
    /// instead").
    var showsMethodChooser: Bool {
        isConnectionGuideEnabled && availableMethods.count > 1
    }

    /// Whether Save can run: a name for the key-file form; something picked
    /// (and, for Play, a name) after signing in with Google.
    var canSave: Bool {
        if isGoogleSignInMode {
            guard google.step == .picking, !google.selectedIds.isEmpty else { return false }
            return providerType != .googlePlay || !accountName.trimmingCharacters(in: .whitespaces).isEmpty
        }
        return !accountName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var isBusy: Bool {
        isValidating || google.step == .signingIn || google.step == .loading
    }
}

/// How a new Play / Firebase account authenticates in Add Account (plan G2).
enum AddAccountCredentialMode: Equatable {
    /// "Sign in with Google": the primary path.
    case googleSignIn
    /// The service account JSON (or, for App Store Connect, the .p8 key): the
    /// advanced path, and the only one when Google sign-in is unavailable.
    case keyFile
}

/// The Google sign-in part of Add Account.
struct GoogleSignInState: Equatable {

    enum Step: Equatable {
        /// Not signed in yet (or the sign-in was cancelled / failed).
        case idle
        /// Google's page is open.
        case signingIn
        /// Listing the Play apps / Firebase projects of the login.
        case loading
        /// The list is shown: pick what to add.
        case picking
    }

    struct Item: Identifiable, Equatable {
        let resource: GoogleAccessibleResource
        /// Already added with this Google login: shown, not selectable.
        let isAlreadyAdded: Bool
        var id: String { resource.id }
    }

    var step: Step = .idle
    var login: GoogleLogin?
    /// The login was new to the device when signed in here.
    var isNewLogin = false
    var items: [Item] = []
    var selectedIds: Set<String> = []
    /// Features left off by unticked checkboxes on the consent page (plan R4).
    var disabledFeatures: [GoogleScopeFeature] = []
    /// The scopes behind `disabledFeatures`, asked again by "Grant Access".
    var missingScopes: [String] = []
    /// A failure to show (sign-in or listing).
    var errorMessage: String?
    /// Information, e.g. a login signed in again whose accounts work again.
    var notice: String?

    var selectableItems: [Item] { items.filter { !$0.isAlreadyAdded } }
    var areAllSelected: Bool {
        let selectable = selectableItems
        return !selectable.isEmpty && selectable.allSatisfy { selectedIds.contains($0.id) }
    }
}

// MARK: - Implementation

@MainActor
final class AddAccountViewModel: AddAccountViewModelProtocol {

    /// Builds the Google Play connection used to validate a new key against the
    /// live service. Injected so tests never hit the network or the Rust core.
    typealias GooglePlayConnectionFactory = (GooglePlayCredentials) -> any GooglePlayAccountConnecting

    @Published var uiState: AddAccountUiState

    private let storage: PersistentStorable
    private let keychain: KeyStorable
    private let googlePlayConnectionFactory: GooglePlayConnectionFactory
    private let analytics: AnalyticsTracking
    private let googleAuth: any GoogleAuthServicing
    private let googleResources: any GoogleResourceListing
    private let connectionGuide: any ConnectionGuideStoring

    init(
        providerType: ProviderType,
        storage: PersistentStorable? = nil,
        keychain: KeyStorable = KeychainStorable.shared,
        googlePlayConnectionFactory: @escaping GooglePlayConnectionFactory = { GooglePlayAccountConnection(credentials: $0) },
        analytics: AnalyticsTracking = AnalyticsService.shared,
        featureFlags: FeatureFlags = .shared,
        googleAuth: (any GoogleAuthServicing)? = nil,
        googleResources: (any GoogleResourceListing)? = nil,
        connectionGuide: any ConnectionGuideStoring = ConnectionGuideStore()
    ) {
        let googleAuth = googleAuth ?? GoogleAuthService.shared
        self.uiState = AddAccountUiState(providerType: providerType)
        self.storage = storage ?? SwiftDataStorable.shared
        self.keychain = keychain
        self.googlePlayConnectionFactory = googlePlayConnectionFactory
        self.analytics = analytics
        self.googleAuth = googleAuth
        self.googleResources = googleResources ?? GoogleResourceDirectory(tokens: googleAuth)
        self.connectionGuide = connectionGuide

        let offersGoogle = featureFlags.isEnabled(.googleSignIn)
            && googleAuth.isConfigured
            && !GoogleScopeFeature.features(for: providerType).isEmpty
        uiState.isGoogleSignInAvailable = offersGoogle
        uiState.credentialMode = offersGoogle ? .googleSignIn : .keyFile
        uiState.isAppleIdSignInAvailable = providerType == .apple && featureFlags.isEnabled(.appleIdSignIn)

        uiState.availableMethods = AccountConnectionMethod.available(
            for: providerType,
            appleIdSignIn: uiState.isAppleIdSignInAvailable,
            googleSignIn: offersGoogle
        )
        uiState.isConnectionGuideEnabled = featureFlags.isEnabled(.accountConnectionGuide)
        uiState.root = Self.initialRoot(
            isGuideEnabled: uiState.isConnectionGuideEnabled,
            hasShownGuide: connectionGuide.hasShownGuide,
            methodCount: uiState.availableMethods.count
        )
    }

    /// Flag OFF: the form, as before. ON: the guide before the first
    /// connection, then the chooser — or the form when there is nothing to
    /// choose.
    static func initialRoot(isGuideEnabled: Bool, hasShownGuide: Bool, methodCount: Int) -> AddAccountRoot {
        guard isGuideEnabled else { return .form }
        if !hasShownGuide { return .connectionGuide }
        return methodCount > 1 ? .methods : .form
    }

    func save() async {
        analytics.track(.buttonTap(.save, on: .addAccount))
        let isGoogle = uiState.isGoogleSignInMode
        let outcome: (failure: AnalyticsErrorCategory?, count: Int)
        if isGoogle {
            outcome = await performGoogleSave()
        } else {
            outcome = (await performSave(), 1)
        }
        var parameters: [String: AnalyticsValue] = [AnalyticsParameterKey.kind: .string(uiState.providerType.rawValue)]
        if isGoogle {
            // Key-file creates keep their historic parameters (no auth_method).
            parameters[AnalyticsParameterKey.authMethod] = .string(AccountAuthMethod.googleSignIn.analyticsValue)
            if outcome.failure == nil {
                parameters[AnalyticsParameterKey.count] = .int(outcome.count)
            }
        }
        if let failure = outcome.failure {
            parameters.merge(failure.parameters) { _, category in category }
        }
        analytics.track(.action(
            .createAccount,
            on: .addAccount,
            result: outcome.failure == nil ? .success : .failure,
            parameters: parameters
        ))
    }

    /// - Returns: why nothing was saved (for analytics only — the user sees
    ///   `validationError`), or `nil` once the account is saved.
    private func performSave() async -> AnalyticsErrorCategory? {
        guard !uiState.accountName.trimmingCharacters(in: .whitespaces).isEmpty else {
            uiState.validationError = String(localized: "Account name is required.")
            return .validation
        }

        if uiState.providerType == .googlePlay, !GooglePlayDeveloperId.isAcceptable(uiState.googlePlayDeveloperId) {
            let input = uiState.googlePlayDeveloperId
            // The input isn't known to be an ID (it may be any pasted text): private.
            Log.print.error("[AddAccount] Developer ID refused by the normalizer — length: \(input.count, privacy: .public), input: \"\(input)\"")
            uiState.validationError = GooglePlayDeveloperId.invalidMessage
            return .validation
        }

        uiState.isValidating = true
        uiState.validationError = nil
        defer { uiState.isValidating = false }

        do {
            // Check for duplicate credentials
            if let duplicateError = await checkDuplicateCredentials() {
                uiState.validationError = duplicateError
                return .duplicate
            }

            // The role picker is hidden for providers without roles (Google
            // Play): those accounts always keep the default role.
            let account = AccountModel(
                name: uiState.accountName.trimmingCharacters(in: .whitespaces),
                providerType: uiState.providerType,
                role: uiState.providerType.supportsAccountRole ? uiState.role : .unspecified,
                googlePlayDeveloperId: uiState.providerType == .googlePlay
                    ? GooglePlayDeveloperId.normalized(uiState.googlePlayDeveloperId)
                    : nil
            )

            switch uiState.providerType {
            case .apple:
                let key = sanitizedPrivateKey(uiState.privateKey)
                let credentials = AppleCredentials(
                    issuerID: uiState.issuerID.trimmingCharacters(in: .whitespaces),
                    privateKeyID: uiState.privateKeyID.trimmingCharacters(in: .whitespaces),
                    privateKey: key
                )

                let connection = AppleAccountConnection(credentials: credentials)
                try await connection.validateCredentials()

                keychain.setObject(credentials, forKey: "credentials.\(account.id)")

            case .firebase:
                let json = uiState.firebaseJSON.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !json.isEmpty else {
                    uiState.validationError = String(localized: "Service Account JSON is required.")
                    return .validation
                }

                guard let jsonData = json.data(using: .utf8) else {
                    uiState.validationError = String(localized: "Invalid JSON format.")
                    return .validation
                }

                let config = try FirebaseConfiguration(serviceAccountJSON: jsonData)
                let provider = BackendEnvironment.firebaseProviders.makeProvider(configuration: config)
                let _ = try await provider.request(FirebaseAPI.v1beta1.projects.get())

                let credentials = FirebaseCredentials(serviceAccountJSON: json)
                keychain.setObject(credentials, forKey: "credentials.\(account.id)")

            case .googlePlay:
                let json = uiState.googlePlayJSON.trimmingCharacters(in: .whitespacesAndNewlines)

                // Offline format check first (empty / malformed / not a service
                // account), then the live check: token exchange + Play Developer
                // Reporting API through the Rust core.
                _ = try GooglePlayServiceAccount(json: json)

                // Storage format unchanged (plan D2): the whole JSON file.
                let credentials = GooglePlayCredentials(serviceAccountJSON: json)
                try await googlePlayConnectionFactory(credentials).validateCredentials()

                keychain.setObject(credentials, forKey: "credentials.\(account.id)")
            }

            do {
                try await storage.save(account, id: account.id)
            } catch {
                uiState.validationError = error.userFacingMessage
                Log.print.error("[AddAccount] Saving the account failed: \(error.localizedDescription)")
                return .storage
            }
            uiState.isSaved = true
            AccountsChange.post()
            Log.print.info("[AddAccount] Account saved: \(account.name)")
            return nil

        } catch {
            uiState.validationError = friendlyMessage(for: error)
            Log.print.error("[AddAccount] Validation failed: \(error.localizedDescription)")
            return AnalyticsErrorCategory(connectionError: error)
        }
    }

    // MARK: - Sign in with Google

    func setCredentialMode(_ mode: AddAccountCredentialMode) {
        guard mode != uiState.credentialMode, mode == .keyFile || uiState.isGoogleSignInAvailable else { return }
        analytics.track(.buttonTap(mode == .keyFile ? .useServiceAccount : .useGoogleSignIn, on: .addAccount))
        uiState.credentialMode = mode
        uiState.validationError = nil
    }

    func signInWithGoogle() async {
        guard uiState.isGoogleSignInMode, !uiState.isBusy else { return }
        analytics.track(.buttonTap(.signInWithGoogle, on: .addAccount))
        analytics.track(.action(.googleSignInStarted, on: .addAccount, parameters: kindParameters))

        let previous = uiState.google
        uiState.google.errorMessage = nil
        uiState.google.notice = nil
        uiState.validationError = nil
        uiState.google.step = .signingIn

        do {
            let result = try await googleAuth.signIn(scopes: GoogleOAuthScope.signIn)
            let usable = applyGrant(result)
            trackSignIn(result: usable ? .success : .failure, missingScopeCount: result.missingScopes.count, failure: usable ? nil : .scopeDenied)
            if usable {
                await loadGoogleResources(isReturningLogin: !result.isNewLogin)
            }
        } catch {
            handleSignInError(error, restoring: previous)
        }
    }

    func grantMissingGoogleAccess() async {
        guard let login = uiState.google.login, !uiState.google.missingScopes.isEmpty, !uiState.isBusy else { return }
        analytics.track(.buttonTap(.grantMissingAccess, on: .addAccount))

        let previous = uiState.google
        let wasUsable = previous.step == .picking
        uiState.google.errorMessage = nil
        uiState.google.step = .signingIn

        do {
            let result = try await googleAuth.requestAdditionalScopes(uiState.google.missingScopes, for: login.loginId)
            let missing = googleAuth.missingScopes(GoogleOAuthScope.signIn, for: login.loginId)
            let usable = applyGrant(GoogleSignInResult(
                login: result.login,
                requestedScopes: result.requestedScopes,
                missingScopes: missing,
                isNewLogin: false
            ))
            trackSignIn(result: usable ? .success : .failure, missingScopeCount: missing.count, failure: usable ? nil : .scopeDenied)
            if usable {
                if wasUsable {
                    uiState.google.step = .picking
                    uiState.google.items = previous.items
                    uiState.google.selectedIds = previous.selectedIds
                } else {
                    await loadGoogleResources(isReturningLogin: true)
                }
            }
        } catch {
            handleSignInError(error, restoring: previous)
        }
    }

    func toggleGoogleItem(_ id: String) {
        guard uiState.google.selectableItems.contains(where: { $0.id == id }) else { return }
        if uiState.google.selectedIds.contains(id) {
            uiState.google.selectedIds.remove(id)
        } else {
            uiState.google.selectedIds.insert(id)
        }
    }

    func setAllGoogleItemsSelected(_ selected: Bool) {
        analytics.track(.buttonTap(selected ? .selectAll : .selectNone, on: .addAccount))
        uiState.google.selectedIds = selected ? Set(uiState.google.selectableItems.map(\.id)) : []
    }

    func discardUnsavedGoogleLogin() async {
        guard !uiState.isSaved, uiState.google.isNewLogin, let login = uiState.google.login else { return }
        let all = (try? await storage.fetchAll(AccountModel.self)) ?? []
        guard GoogleLoginReferences.accounts(using: login.loginId, in: all, keychain: keychain).isEmpty else { return }
        Log.print.info("[AddAccount] Closed without saving: signing out the unused Google login")
        await googleAuth.signOut(loginId: login.loginId)
    }

    // MARK: - Sign in with Apple ID

    func openAppleIdSignIn() {
        guard uiState.isAppleIdSignInAvailable, !uiState.isBusy else { return }
        analytics.track(.buttonTap(.signInWithAppleId, on: .addAccount))
        uiState.validationError = nil
        uiState.isShowingAppleIdSignIn = true
    }

    // MARK: - Connection guide and method chooser

    func connectionGuideDidAppear() {
        guard uiState.root == .connectionGuide else { return }
        connectionGuide.markGuideShown()
    }

    func finishConnectionGuide() {
        guard uiState.root == .connectionGuide else { return }
        // Also recorded here, should the guide never have reported appearing.
        connectionGuide.markGuideShown()
        uiState.root = uiState.availableMethods.count > 1 ? .methods : .form
        Log.print.info("[AddAccount] Connection guide done: \(self.uiState.availableMethods.count, privacy: .public) method(s) for \(self.uiState.providerType.rawValue, privacy: .public)")
    }

    func showConnectionGuide() {
        guard uiState.isConnectionGuideEnabled, uiState.root != .connectionGuide,
              !uiState.isShowingConnectionGuide, !uiState.isBusy else { return }
        analytics.track(.buttonTap(.howItWorks, on: currentScreen))
        uiState.isShowingConnectionGuide = true
    }

    func chooseMethod(_ method: AccountConnectionMethod) {
        guard uiState.showsMethodChooser, uiState.availableMethods.contains(method), !uiState.isBusy else { return }
        analytics.track(.buttonTap(.connectionMethodButton(for: method), on: .addAccountMethod))
        uiState.validationError = nil
        uiState.chosenMethod = method
        switch method {
        case .appleIdSignIn:
            uiState.isShowingAppleIdSignIn = true
        case .apiKey, .serviceAccount:
            uiState.credentialMode = .keyFile
            uiState.isShowingMethodForm = true
        case .googleSignIn:
            uiState.credentialMode = .googleSignIn
            uiState.isShowingMethodForm = true
        }
    }

    /// The tracked screen on top: the chooser, or the form (root or pushed).
    private var currentScreen: AnalyticsScreen {
        uiState.root == .methods && !uiState.isShowingMethodForm ? .addAccountMethod : .addAccount
    }

    // MARK: Sign in with Google — private

    private var kindParameters: [String: AnalyticsValue] {
        [AnalyticsParameterKey.kind: .string(uiState.providerType.rawValue)]
    }

    private func trackSignIn(result: AnalyticsResult, missingScopeCount: Int? = nil, failure: AnalyticsErrorCategory? = nil) {
        var parameters = kindParameters
        if let missingScopeCount {
            parameters[AnalyticsParameterKey.missingScopeCount] = .int(missingScopeCount)
        }
        if let failure {
            parameters.merge(failure.parameters) { _, category in category }
        }
        analytics.track(.action(.googleSignIn, on: .addAccount, result: result, parameters: parameters))
    }

    /// Keeps the login and works out which features the missing scopes turn
    /// off. - Returns: whether the provider can list anything to add.
    private func applyGrant(_ result: GoogleSignInResult) -> Bool {
        let provider = uiState.providerType
        if uiState.google.login?.loginId != result.login.loginId {
            uiState.google.isNewLogin = result.isNewLogin
        }
        uiState.google.login = result.login
        uiState.google.disabledFeatures = GoogleScopeFeature.disabled(by: result.missingScopes, for: provider)
        uiState.google.missingScopes = uiState.google.disabledFeatures.map(\.scope)

        let requiredMissing = GoogleScopeFeature.requiredScopes(for: provider).filter(result.missingScopes.contains)
        guard requiredMissing.isEmpty else {
            Log.print.notice("[AddAccount] Google sign-in without a required scope (\(requiredMissing.count, privacy: .public) missing)")
            uiState.google.step = .idle
            uiState.google.items = []
            uiState.google.selectedIds = []
            uiState.google.errorMessage = String(localized: "Google didn't grant the access StackConnect needs to list your \(provider.displayName) data. Tap Grant Access and keep every checkbox ticked.")
            return false
        }
        if provider == .googlePlay, uiState.accountName.trimmingCharacters(in: .whitespaces).isEmpty {
            uiState.accountName = result.login.email ?? ""
        }
        return true
    }

    private func handleSignInError(_ error: Error, restoring previous: GoogleSignInState) {
        if case GoogleAuthError.cancelled = error {
            Log.print.info("[AddAccount] Google sign-in cancelled")
            uiState.google = previous
            uiState.google.errorMessage = nil
            trackSignIn(result: .cancelled)
            return
        }
        uiState.google = previous
        uiState.google.errorMessage = error.userFacingMessage
        Log.print.error("[AddAccount] Google sign-in failed: \(error.localizedDescription, privacy: .public)")
        trackSignIn(result: .failure, failure: AnalyticsErrorCategory(connectionError: error))
    }

    /// Lists the Play apps / Firebase projects of the login and marks those
    /// already added with it.
    private func loadGoogleResources(isReturningLogin: Bool) async {
        guard let login = uiState.google.login else { return }
        uiState.google.step = .loading

        let resources: [GoogleAccessibleResource]
        do {
            switch uiState.providerType {
            case .googlePlay: resources = try await googleResources.playApps(loginId: login.loginId)
            case .firebase:   resources = try await googleResources.firebaseProjects(loginId: login.loginId)
            case .apple:      resources = []
            }
        } catch {
            uiState.google.step = .idle
            uiState.google.errorMessage = error.userFacingMessage
            Log.print.error("[AddAccount] Listing what the Google login can access failed: \(error.localizedDescription, privacy: .public)")
            analytics.track(.action(.load, on: .addAccount, result: .failure,
                                    parameters: kindParameters.merging(AnalyticsErrorCategory.parameters(for: error)) { _, new in new }))
            return
        }

        let existing = await existingAccounts(using: login.loginId)
        let added = alreadyAddedIds(by: existing, among: resources)
        uiState.google.items = resources.map { GoogleSignInState.Item(resource: $0, isAlreadyAdded: added.contains($0.id)) }
        uiState.google.selectedIds = Set(uiState.google.selectableItems.map(\.id))
        uiState.google.step = .picking

        if isReturningLogin, !existing.isEmpty {
            uiState.google.notice = String(localized: "You signed in again as \(login.displayName). Accounts already added with this Google account work again.")
        }
        if resources.isEmpty {
            uiState.google.errorMessage = uiState.providerType == .googlePlay
                ? String(localized: "This Google account can't see any Google Play app. Sign in with the account that has access in Play Console.")
                : String(localized: "This Google account can't see any Firebase project. Sign in with the account that has access in the Firebase console.")
        }
    }

    private func existingAccounts(using loginId: String) async -> [AccountModel] {
        let all = (try? await storage.fetchAll(AccountModel.self)) ?? []
        let sameProvider = all.filter { $0.providerType == uiState.providerType }
        return GoogleLoginReferences.accounts(using: loginId, in: sameProvider, keychain: keychain)
    }

    /// Play: what an existing Play account of this login already covers (all
    /// apps when it has no scope). Firebase: the project of each account.
    private func alreadyAddedIds(by accounts: [AccountModel], among resources: [GoogleAccessibleResource]) -> Set<String> {
        var ids = Set<String>()
        for account in accounts {
            for resource in resources where account.allowsApp(bundleId: resource.id) {
                ids.insert(resource.id)
            }
        }
        return ids
    }

    /// Creates the accounts picked after signing in with Google.
    /// - Returns: why nothing was saved (analytics only) and how many accounts were added.
    private func performGoogleSave() async -> (failure: AnalyticsErrorCategory?, count: Int) {
        guard let login = uiState.google.login, uiState.google.step == .picking else {
            uiState.validationError = String(localized: "Sign in with Google first.")
            return (.validation, 0)
        }
        let selected = uiState.google.selectableItems.filter { uiState.google.selectedIds.contains($0.id) }
        guard !selected.isEmpty else {
            uiState.validationError = uiState.providerType == .googlePlay
                ? String(localized: "Select at least one app.")
                : String(localized: "Select at least one project.")
            return (.validation, 0)
        }

        uiState.isValidating = true
        uiState.validationError = nil
        defer { uiState.isValidating = false }

        let accounts: [AccountModel]
        switch uiState.providerType {
        case .googlePlay:
            let name = uiState.accountName.trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else {
                uiState.validationError = String(localized: "Account name is required.")
                return (.validation, 0)
            }
            guard GooglePlayDeveloperId.isAcceptable(uiState.googlePlayDeveloperId) else {
                uiState.validationError = GooglePlayDeveloperId.invalidMessage
                return (.validation, 0)
            }
            if let existing = await existingAccounts(using: login.loginId).first {
                // One Play account per Google login: the sync would fetch the
                // same apps twice otherwise.
                uiState.validationError = String(localized: "This Google account is already added as \"\(existing.name)\".")
                return (.duplicate, 0)
            }
            // Everything picked ⇒ no scope, so apps added later in Play Console show up too.
            let everything = selected.count == uiState.google.items.count
            accounts = [AccountModel(
                name: name,
                providerType: .googlePlay,
                appsBundles: everything ? nil : selected.map(\.id).sorted(),
                googlePlayDeveloperId: GooglePlayDeveloperId.normalized(uiState.googlePlayDeveloperId),
                authMethod: .googleSignIn
            )]
        case .firebase:
            // One account per project, named after it: the same shape as a
            // project's service account (plan G5).
            accounts = selected.map { item in
                AccountModel(
                    name: item.resource.title,
                    providerType: .firebase,
                    appsBundles: [item.id],
                    authMethod: .googleSignIn
                )
            }
        case .apple:
            return (.validation, 0)
        }

        var saved = 0
        for account in accounts {
            switch account.providerType {
            case .googlePlay:
                keychain.setObject(GooglePlayCredentials(googleLoginId: login.loginId), forKey: "credentials.\(account.id)")
            default:
                keychain.setObject(FirebaseCredentials(googleLoginId: login.loginId), forKey: "credentials.\(account.id)")
            }
            do {
                try await storage.save(account, id: account.id)
                saved += 1
            } catch {
                keychain.removeObject(forKey: "credentials.\(account.id)")
                Log.print.error("[AddAccount] Saving a Google sign-in account failed: \(error.localizedDescription)")
                uiState.validationError = error.userFacingMessage
                if saved > 0 { AccountsChange.post() }
                return (.storage, saved)
            }
        }

        uiState.isSaved = true
        AccountsChange.post()
        Log.print.info("[AddAccount] Added \(saved, privacy: .public) \(self.uiState.providerType.rawValue, privacy: .public) account(s) with Google sign-in")
        return (nil, saved)
    }

    // MARK: - Private

    private func friendlyMessage(for error: Error) -> String {
        switch uiState.providerType {
        case .googlePlay:
            return GooglePlayErrorTranslator.friendlyMessage(for: error)
        case .apple, .firebase:
            return error.userFacingMessage
        }
    }

    private func sanitizedPrivateKey(_ key: String) -> String {
        key
            .replacingOccurrences(of: "-----BEGIN PRIVATE KEY-----", with: "")
            .replacingOccurrences(of: "-----END PRIVATE KEY-----", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .trimmingCharacters(in: .whitespaces)
    }

    private func checkDuplicateCredentials() async -> String? {
        guard let allAccounts = try? await storage.fetchAll(AccountModel.self) else { return nil }
        let sameTypeAccounts = allAccounts.filter { $0.providerType == uiState.providerType }
        let newName = uiState.accountName.trimmingCharacters(in: .whitespaces)

        // Google Play: same service account = same `client_email` (plan D4), so a
        // re-formatted or re-downloaded key of that account is caught too. An
        // unparseable new key is not a duplicate: save() reports why.
        if uiState.providerType == .googlePlay {
            guard let existing = GooglePlayDuplicateAccountFinder.existingAccount(
                matching: uiState.googlePlayJSON,
                in: sameTypeAccounts,
                keychain: keychain
            ) else {
                return nil
            }
            return String(localized: "An account with these credentials already exists: \"\(existing.name)\".")
        }

        for existing in sameTypeAccounts {
            switch uiState.providerType {
            case .apple:
                // Same team key may be registered again under a different name/role.
                // Only block an EXACT duplicate: same private key AND same account name.
                if let creds: AppleCredentials = keychain.object(forKey: "credentials.\(existing.id)") {
                    let newKey = sanitizedPrivateKey(uiState.privateKey)
                    if creds.privateKey == newKey && existing.name == newName {
                        return String(localized: "An account with these credentials already exists: \"\(existing.name)\".")
                    }
                }
            case .firebase:
                if let creds: FirebaseCredentials = keychain.object(forKey: "credentials.\(existing.id)") {
                    let newJSON = uiState.firebaseJSON.trimmingCharacters(in: .whitespacesAndNewlines)
                    if creds.serviceAccountJSON == newJSON {
                        return String(localized: "An account with these credentials already exists: \"\(existing.name)\".")
                    }
                }
            case .googlePlay:
                break // Handled above.
            }
        }

        return nil
    }
}
