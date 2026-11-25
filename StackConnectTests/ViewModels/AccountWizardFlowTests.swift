import XCTest
@testable import StackConnect

/// The wizard's config and step engine (plan `unified-accounts.md` §3.1 and
/// §3.2): one test per row of the parameters table, in Debug (sign-in flags
/// ON) and Release (OFF), plus reconnecting.
@MainActor
final class AccountWizardFlowTests: XCTestCase {

    private var suites: [String] = []

    override func tearDown() async throws {
        for suite in suites { UserDefaults().removePersistentDomain(forName: suite) }
        suites = []
        try await super.tearDown()
    }

    /// Debug: both sign-in flags ON. Release: both OFF (their Release default).
    private func flags(signIn: Bool, googlePlay: Bool = true, guide: Bool = true) -> FeatureFlags {
        let suite = "AccountWizardFlowTests.\(UUID().uuidString)"
        suites.append(suite)
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.set(signIn, forKey: FeatureFlag.appleIdSignIn.rawValue)
        defaults.set(signIn, forKey: FeatureFlag.googleSignIn.rawValue)
        defaults.set(googlePlay, forKey: FeatureFlag.googlePlayAccounts.rawValue)
        defaults.set(guide, forKey: FeatureFlag.accountConnectionGuide.rawValue)
        return FeatureFlags(defaults: defaults, remoteValues: StubRemoteFeatureValues())
    }

    private func config(_ entry: AccountWizardEntry = .chooseKind, signIn: Bool, googlePlay: Bool = true, configured: Bool = true) -> AccountWizardConfig {
        AccountWizardConfig.make(entry: entry, featureFlags: flags(signIn: signIn, googlePlay: googlePlay), isGoogleSignInConfigured: configured)
    }

    private func steps(_ config: AccountWizardConfig, kind: AccountWizardKind, method: AccountWizardMethod) -> [AccountWizardStep] {
        AccountWizardFlow.steps(entry: config.entry, kind: config.kindConfig(for: kind), method: method)
    }

    // MARK: - Type step

    func testTypeStepListsTheStoresInOrderThenTheImport() {
        let debug = config(signIn: true)

        XCTAssertEqual(debug.kinds.map(\.kind), [.provider(.apple), .provider(.googlePlay), .provider(.firebase), .importFile])
        XCTAssertEqual(debug.providerKinds.map(\.kind), [.provider(.apple), .provider(.googlePlay), .provider(.firebase)])
        XCTAssertEqual(debug.importKind?.kind, .importFile)
    }

    func testChooseKindStartsOnTypeWithTheShortestPath() {
        let debug = config(signIn: true)

        XCTAssertNil(debug.initialKind)
        XCTAssertNil(debug.initialMethod)
        XCTAssertEqual(AccountWizardFlow.steps(entry: .chooseKind, kind: nil, method: nil), [.type, .credentials, .review])
    }

    // MARK: - App Store Connect

    func testAppStoreConnectWithAnApiKeyInDebug() {
        let debug = config(signIn: true)
        let kind = debug.kindConfig(for: .provider(.apple))

        XCTAssertEqual(kind?.methods, [.apiKey, .appleIdSignIn])
        XCTAssertEqual(kind?.selection, SelectionStep(kind: .team, onlyFor: .appleIdSignIn, allowsMultiple: true))
        XCTAssertEqual(kind?.supportsRole, true)
        XCTAssertEqual(steps(debug, kind: .provider(.apple), method: .apiKey), [.type, .method, .credentials, .review])
    }

    func testAppStoreConnectWithEmailAndPasswordInDebug() {
        let debug = config(signIn: true)

        XCTAssertEqual(steps(debug, kind: .provider(.apple), method: .appleIdSignIn),
                       [.type, .method, .credentials, .code, .items, .review])
    }

    func testAppStoreConnectInReleaseHasNoMethodStep() {
        let release = config(signIn: false)
        let kind = release.kindConfig(for: .provider(.apple))

        XCTAssertEqual(kind?.methods, [.apiKey])
        XCTAssertEqual(kind?.showsMethodStep, false)
        XCTAssertEqual(kind?.defaultMethod, .apiKey)
        XCTAssertEqual(steps(release, kind: .provider(.apple), method: .apiKey), [.type, .credentials, .review])
    }

    // MARK: - Google Play

    func testGooglePlayWithAGoogleAccountInDebug() {
        let debug = config(signIn: true)
        let kind = debug.kindConfig(for: .provider(.googlePlay))

        XCTAssertEqual(kind?.methods, [.serviceAccount, .googleSignIn], "The file method first, none promoted")
        XCTAssertEqual(kind?.selection?.kind, .apps)
        XCTAssertEqual(kind?.supportsRole, false)
        XCTAssertEqual(steps(debug, kind: .provider(.googlePlay), method: .googleSignIn),
                       [.type, .method, .credentials, .items, .review])
    }

    func testGooglePlayWithAServiceAccountInDebug() {
        let debug = config(signIn: true)

        XCTAssertEqual(steps(debug, kind: .provider(.googlePlay), method: .serviceAccount),
                       [.type, .method, .credentials, .review])
    }

    func testGooglePlayIsHiddenWhileItsFlagIsOff() {
        let hidden = config(signIn: true, googlePlay: false)

        XCTAssertNil(hidden.kindConfig(for: .provider(.googlePlay)))
        XCTAssertEqual(hidden.kinds.map(\.kind), [.provider(.apple), .provider(.firebase), .importFile])
        XCTAssertNil(AccountWizardConfig.make(entry: .kind(.provider(.googlePlay)), featureFlags: flags(signIn: true, googlePlay: false), isGoogleSignInConfigured: true).initialKind)
    }

    // MARK: - Firebase

    func testFirebaseWithAGoogleAccountInDebug() {
        let debug = config(signIn: true)
        let kind = debug.kindConfig(for: .provider(.firebase))

        XCTAssertEqual(kind?.methods, [.serviceAccount, .googleSignIn])
        XCTAssertEqual(kind?.selection?.kind, .projects)
        XCTAssertEqual(kind?.supportsRole, true)
        XCTAssertEqual(steps(debug, kind: .provider(.firebase), method: .googleSignIn),
                       [.type, .method, .credentials, .items, .review])
    }

    func testFirebaseInReleaseHasNoMethodStep() {
        let release = config(signIn: false)
        let kind = release.kindConfig(for: .provider(.firebase))

        XCTAssertEqual(kind?.methods, [.serviceAccount])
        // A service account key belongs to one project: no Projects step.
        XCTAssertEqual(steps(release, kind: .provider(.firebase), method: .serviceAccount), [.type, .credentials, .review])
    }

    func testGoogleSignInNeedsAnOAuthClientToo() {
        let unconfigured = config(signIn: true, configured: false)

        XCTAssertEqual(unconfigured.kindConfig(for: .provider(.firebase))?.methods, [.serviceAccount])
        XCTAssertEqual(unconfigured.kindConfig(for: .provider(.googlePlay))?.methods, [.serviceAccount])
        XCTAssertEqual(unconfigured.kindConfig(for: .provider(.apple))?.methods, [.apiKey, .appleIdSignIn])
    }

    // MARK: - Import

    func testImportFileInDebugAndRelease() {
        for signIn in [true, false] {
            let config = config(signIn: signIn)
            let kind = config.kindConfig(for: .importFile)

            XCTAssertEqual(kind?.methods, [.scexportFile])
            XCTAssertNil(kind?.selection)
            XCTAssertEqual(kind?.supportsRole, false)
            XCTAssertEqual(steps(config, kind: .importFile, method: .scexportFile), [.type, .credentials, .review])
        }
    }

    func testImportEntrySkipsTheTypeStep() {
        let entry = config(.kind(.importFile), signIn: true)

        XCTAssertEqual(entry.initialKind?.kind, .importFile)
        XCTAssertEqual(entry.initialMethod, .scexportFile)
        XCTAssertEqual(steps(entry, kind: .importFile, method: .scexportFile), [.credentials, .review])
    }

    func testStoreEntrySkipsTheTypeStepAndKeepsTheMethodStep() {
        let entry = config(.kind(.provider(.apple)), signIn: true)

        XCTAssertEqual(entry.initialKind?.kind, .provider(.apple))
        XCTAssertNil(entry.initialMethod, "Two methods: the user picks one")
        XCTAssertEqual(AccountWizardFlow.steps(entry: entry.entry, kind: entry.initialKind, method: nil),
                       [.method, .credentials, .review])
    }

    // MARK: - Auth styles

    func testEveryMethodMapsToItsAuthStyle() {
        XCTAssertEqual(AccountWizardMethod.apiKey.authStyle, .configFile(fields: [.issuerID, .keyID], fileTypes: AuthStyle.p8FileTypes))
        XCTAssertEqual(AccountWizardMethod.serviceAccount.authStyle, .configFile(fields: [], fileTypes: [.json]))
        XCTAssertEqual(AccountWizardMethod.scexportFile.authStyle, .configFile(fields: [.filePassword], fileTypes: [.data]))
        XCTAssertEqual(AccountWizardMethod.appleIdSignIn.authStyle, .credentials(twoFactor: true))
        XCTAssertEqual(AccountWizardMethod.googleSignIn.authStyle, .webSignIn)
        XCTAssertNil(AccountWizardMethod.scexportFile.connectionMethod, "The import is never a connection guide method")
        for method in AccountConnectionMethod.allCases {
            XCTAssertEqual(AccountWizardMethod(method).connectionMethod, method)
        }
    }

    // MARK: - Reconnect

    func testReconnectingAnAppleIdAccountRunsCredentialsThenCode() {
        let account = AccountModel(name: "Personal", providerType: .apple, authMethod: .appleIdSignIn)
        let reconnect = config(.reconnect(account), signIn: false)

        XCTAssertEqual(reconnect.initialMethod, .appleIdSignIn, "Not gated by the flags: accounts already added keep working")
        XCTAssertEqual(AccountWizardFlow.steps(entry: reconnect.entry, kind: reconnect.initialKind, method: reconnect.initialMethod),
                       [.credentials, .code])
    }

    func testReconnectingAGoogleAccountRunsCredentialsOnly() {
        let account = AccountModel(name: "Client", providerType: .googlePlay, authMethod: .googleSignIn)
        let reconnect = config(.reconnect(account), signIn: true)

        XCTAssertEqual(reconnect.initialMethod, .googleSignIn)
        XCTAssertEqual(AccountWizardFlow.steps(entry: reconnect.entry, kind: reconnect.initialKind, method: reconnect.initialMethod),
                       [.credentials])
    }

    func testReconnectingAnExpiredImportImportsItAgain() {
        let account = AccountModel(name: "Shared", providerType: .apple, origin: .imported, expirationDate: .distantPast)
        let reconnect = config(.reconnect(account), signIn: true)

        XCTAssertEqual(reconnect.initialKind?.kind, .importFile)
        XCTAssertEqual(reconnect.initialMethod, .scexportFile)
        XCTAssertEqual(AccountWizardFlow.steps(entry: reconnect.entry, kind: reconnect.initialKind, method: reconnect.initialMethod),
                       [.credentials])
    }

    func testKeyFileAccountsCreatedHereHaveNoReconnect() {
        let account = AccountModel(name: "Key", providerType: .apple)

        XCTAssertFalse(AccountWizardConfig.canReconnect(account))
        XCTAssertNil(AccountWizardConfig.reconnectKind(for: account))
    }
}
