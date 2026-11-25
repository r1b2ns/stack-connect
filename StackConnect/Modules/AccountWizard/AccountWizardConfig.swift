import Foundation
import UniformTypeIdentifiers

// MARK: - Kind

/// What the wizard connects: an account of one store, or a `.scexport` file
/// exported from another device (plan `unified-accounts.md` §3).
enum AccountWizardKind: Hashable, Identifiable {
    case provider(ProviderType)
    case importFile

    var id: String {
        switch self {
        case .provider(let provider): return provider.rawValue
        case .importFile:             return "importFile"
        }
    }

    /// The store, or `nil` for a file (its store is read from the file).
    var provider: ProviderType? {
        if case .provider(let provider) = self { return provider }
        return nil
    }
}

// MARK: - Entry

/// Where the wizard starts.
enum AccountWizardEntry: Hashable, Identifiable {
    /// "+" on the accounts list or "Add account": starts at the Type step.
    case chooseKind
    /// "Add" on a group, or "Import .scexport file": skips the Type step.
    case kind(AccountWizardKind)
    /// A disconnected account: Credentials (+ Code) only, then back to it.
    /// An Apple ID session or a Google login signs in again; an imported
    /// account whose file expired is imported again in place.
    case reconnect(AccountModel)

    var id: String {
        switch self {
        case .chooseKind:            return "chooseKind"
        case .kind(let kind):        return "kind.\(kind.id)"
        case .reconnect(let account): return "reconnect.\(account.id)"
        }
    }

    var isReconnect: Bool {
        if case .reconnect = self { return true }
        return false
    }
}

// MARK: - Method

/// A way to connect in the wizard: the four `AccountConnectionMethod`s of
/// Add Account, plus the `.scexport` file of an import. Kept apart from
/// `AccountConnectionMethod` so the connection guide (which describes only
/// the ways to connect a store) never lists the import.
enum AccountWizardMethod: String, CaseIterable, Hashable, Identifiable {
    case apiKey
    case appleIdSignIn
    case googleSignIn
    case serviceAccount
    case scexportFile

    var id: String { rawValue }

    init(_ method: AccountConnectionMethod) {
        switch method {
        case .apiKey:         self = .apiKey
        case .appleIdSignIn:  self = .appleIdSignIn
        case .googleSignIn:   self = .googleSignIn
        case .serviceAccount: self = .serviceAccount
        }
    }

    /// The store connection method, `nil` for the import.
    var connectionMethod: AccountConnectionMethod? {
        switch self {
        case .apiKey:         return .apiKey
        case .appleIdSignIn:  return .appleIdSignIn
        case .googleSignIn:   return .googleSignIn
        case .serviceAccount: return .serviceAccount
        case .scexportFile:   return nil
        }
    }

    /// How the Credentials step of this method looks and behaves. Each
    /// style has one Credentials component.
    var authStyle: AuthStyle {
        switch self {
        case .apiKey:
            return .configFile(fields: [.issuerID, .keyID], fileTypes: AuthStyle.p8FileTypes)
        case .serviceAccount:
            return .configFile(fields: [], fileTypes: [.json])
        case .scexportFile:
            return .configFile(fields: [.filePassword], fileTypes: [.data])
        case .appleIdSignIn:
            return .credentials(twoFactor: true)
        case .googleSignIn:
            return .webSignIn
        }
    }

    /// The account is a personal sign-in (Apple ID session, Google login).
    var isSignIn: Bool {
        switch authStyle {
        case .credentials, .webSignIn: return true
        case .configFile:              return false
        }
    }
}

// MARK: - Auth style

/// The three Credentials components the wizard knows.
enum AuthStyle: Equatable {
    /// A configuration file (`.p8`, service account JSON, `.scexport`) plus
    /// the fields that go with it.
    case configFile(fields: [AccountWizardField], fileTypes: [UTType])
    /// Email and password, plus a verification code when `twoFactor`.
    case credentials(twoFactor: Bool)
    /// The provider's page in `ASWebAuthenticationSession`.
    case webSignIn

    var usesTwoFactor: Bool {
        if case .credentials(let twoFactor) = self { return twoFactor }
        return false
    }

    static var p8FileTypes: [UTType] {
        var types: [UTType] = []
        if let p8 = UTType(filenameExtension: "p8") { types.append(p8) }
        types.append(contentsOf: [.data, .item])
        return types
    }
}

/// A field shown next to the file of a `.configFile` Credentials step.
enum AccountWizardField: String, Hashable {
    case issuerID
    case keyID
    case filePassword

    var isSecure: Bool { self == .filePassword }
}

// MARK: - Selection

/// The optional Items step: what the credentials give access to.
struct SelectionStep: Equatable {

    enum Kind: Equatable {
        /// App Store Connect teams of an Apple ID.
        case team
        /// Google Play apps of a Google login.
        case apps
        /// Firebase projects of a Google login.
        case projects
    }

    let kind: Kind
    /// The step appears only for this method (`nil`: every method).
    let onlyFor: AccountWizardMethod?
    let allowsMultiple: Bool

    func applies(to method: AccountWizardMethod) -> Bool {
        onlyFor == nil || onlyFor == method
    }
}

// MARK: - Kind parameters

/// Everything the wizard needs to know about one kind: the only thing that
/// changes between account types.
struct AccountWizardKindConfig: Equatable, Identifiable {
    let kind: AccountWizardKind
    /// Already filtered by the feature flags, in display order. Never empty.
    let methods: [AccountWizardMethod]
    let selection: SelectionStep?
    /// The Review step offers a role (App Store Connect, Firebase). Only for
    /// methods whose accounts don't read their role from the store.
    let supportsRole: Bool

    var id: String { kind.id }

    /// The Method step appears only with a real choice.
    var showsMethodStep: Bool { methods.count > 1 }

    /// The single method, chosen without a Method step.
    var defaultMethod: AccountWizardMethod? { methods.count == 1 ? methods.first : nil }
}

// MARK: - Config

/// The wizard's only input (plan `unified-accounts.md` §3): where it starts
/// and the parameters of every kind this build offers.
struct AccountWizardConfig: Equatable {
    let entry: AccountWizardEntry
    /// The kinds of the Type step (and the one an entry names), already
    /// filtered by the feature flags. The import comes last.
    let kinds: [AccountWizardKindConfig]

    /// The kind the entry starts with, or `nil` for `.chooseKind`.
    var initialKind: AccountWizardKindConfig? {
        switch entry {
        case .chooseKind:
            return nil
        case .kind(let kind):
            return kindConfig(for: kind)
        case .reconnect(let account):
            return Self.reconnectKind(for: account)
        }
    }

    /// The method the entry starts with: the reconnected account's, or the
    /// single method of the kind.
    var initialMethod: AccountWizardMethod? {
        if case .reconnect(let account) = entry { return Self.reconnectMethod(for: account) }
        return initialKind?.defaultMethod
    }

    func kindConfig(for kind: AccountWizardKind) -> AccountWizardKindConfig? {
        kinds.first { $0.kind == kind }
    }

    /// The store kinds of the Type step (the import has its own section).
    var providerKinds: [AccountWizardKindConfig] {
        kinds.filter { $0.kind != .importFile }
    }

    var importKind: AccountWizardKindConfig? {
        kindConfig(for: .importFile)
    }
}

// MARK: - Building

extension AccountWizardConfig {

    /// The config of this build.
    /// - Parameters:
    ///   - featureFlags: `googlePlayAccounts` hides Google Play;
    ///     `appleIdSignIn` / `googleSignIn` hide the sign-in methods (both OFF
    ///     in Release, so the Method step disappears there).
    ///   - isGoogleSignInConfigured: the build has an OAuth client ID.
    static func make(
        entry: AccountWizardEntry,
        featureFlags: FeatureFlags = .shared,
        isGoogleSignInConfigured: Bool
    ) -> AccountWizardConfig {
        let appleIdSignIn = featureFlags.isEnabled(.appleIdSignIn)
        let googleSignIn = featureFlags.isEnabled(.googleSignIn) && isGoogleSignInConfigured
        var kinds = featureFlags.availableProviders
            .sorted { displayOrder($0) < displayOrder($1) }
            .map { kindConfig(for: $0, appleIdSignIn: appleIdSignIn, googleSignIn: googleSignIn) }
        kinds.append(importConfig)
        return AccountWizardConfig(entry: entry, kinds: kinds)
    }

    /// App Store Connect, Google Play, Firebase: the order of the lists.
    static func displayOrder(_ provider: ProviderType) -> Int {
        switch provider {
        case .apple:      return 0
        case .googlePlay: return 1
        case .firebase:   return 2
        }
    }

    /// The parameters of `provider` (plan table §3.2). The file method comes
    /// first and no method is promoted over another.
    static func kindConfig(for provider: ProviderType, appleIdSignIn: Bool, googleSignIn: Bool) -> AccountWizardKindConfig {
        switch provider {
        case .apple:
            return AccountWizardKindConfig(
                kind: .provider(.apple),
                methods: appleIdSignIn ? [.apiKey, .appleIdSignIn] : [.apiKey],
                selection: SelectionStep(kind: .team, onlyFor: .appleIdSignIn, allowsMultiple: true),
                supportsRole: true
            )
        case .googlePlay:
            return AccountWizardKindConfig(
                kind: .provider(.googlePlay),
                methods: googleSignIn ? [.serviceAccount, .googleSignIn] : [.serviceAccount],
                selection: SelectionStep(kind: .apps, onlyFor: .googleSignIn, allowsMultiple: true),
                supportsRole: false
            )
        case .firebase:
            return AccountWizardKindConfig(
                kind: .provider(.firebase),
                methods: googleSignIn ? [.serviceAccount, .googleSignIn] : [.serviceAccount],
                selection: SelectionStep(kind: .projects, onlyFor: .googleSignIn, allowsMultiple: true),
                supportsRole: true
            )
        }
    }

    static let importConfig = AccountWizardKindConfig(
        kind: .importFile,
        methods: [.scexportFile],
        selection: nil,
        supportsRole: false
    )

    // MARK: Reconnect

    /// The way `account` connects again, or `nil` when it has none here (a
    /// key file created on this device: remove it and add it again).
    /// Not filtered by the flags: accounts already added keep working
    /// whatever they say.
    static func reconnectMethod(for account: AccountModel) -> AccountWizardMethod? {
        if account.origin == .imported { return .scexportFile }
        switch account.authMethod {
        case .appleIdSignIn: return .appleIdSignIn
        case .googleSignIn:  return .googleSignIn
        case .keyFile:       return nil
        }
    }

    static func reconnectKind(for account: AccountModel) -> AccountWizardKindConfig? {
        guard let method = reconnectMethod(for: account) else { return nil }
        let kind: AccountWizardKind = method == .scexportFile ? .importFile : .provider(account.providerType)
        return AccountWizardKindConfig(kind: kind, methods: [method], selection: nil, supportsRole: false)
    }

    /// Whether `account` can be reconnected from the wizard.
    static func canReconnect(_ account: AccountModel) -> Bool {
        reconnectMethod(for: account) != nil
    }
}

// MARK: - Steps

/// The fixed step template (plan §3.1). Optional steps appear only when the
/// config asks for them; the order never changes.
enum AccountWizardStep: String, Hashable, CaseIterable {
    case type
    case method
    case credentials
    case code
    case items
    case review
}

/// The step engine: which steps a config runs, and in which order.
enum AccountWizardFlow {

    /// - Parameters:
    ///   - kind: the kind chosen (or named by the entry); `nil` while on Type.
    ///   - method: the method chosen; `nil` falls back to the kind's first
    ///     method, so the progress bar has its full length before a choice.
    static func steps(
        entry: AccountWizardEntry,
        kind: AccountWizardKindConfig?,
        method: AccountWizardMethod?
    ) -> [AccountWizardStep] {
        var steps: [AccountWizardStep] = []
        if entry == .chooseKind { steps.append(.type) }
        guard let kind, let method = method ?? kind.methods.first else {
            // Before the type is known: the shortest path.
            return steps + [.credentials, .review]
        }
        let isReconnect = entry.isReconnect
        if !isReconnect, kind.showsMethodStep { steps.append(.method) }
        steps.append(.credentials)
        if method.authStyle.usesTwoFactor { steps.append(.code) }
        if isReconnect { return steps }
        if let selection = kind.selection, selection.applies(to: method) { steps.append(.items) }
        steps.append(.review)
        return steps
    }
}
