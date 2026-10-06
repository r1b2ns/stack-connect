import Foundation

// MARK: - Protocol

@MainActor
protocol GooglePlayAppInfoViewModelProtocol: ObservableObject {
    var uiState: GooglePlayAppInfoUiState { get set }
    /// Loads once per screen (see `GooglePlayAppSectionLoader`).
    func loadIfNeeded() async
    /// Reads again (pull to refresh, Retry).
    func load() async
}

// MARK: - UiState

struct GooglePlayAppInfoUiState: GooglePlayAppSectionUiState {
    var account: AccountModel
    var app: GooglePlayAppItem
    var section = GooglePlayAppSectionState<GooglePlayAppDetailsModel>()

    /// `nil` until loaded (cache or API).
    var details: GooglePlayAppDetailsModel? {
        section.content
    }
}

// MARK: - Implementation

/// "App Details" section of a Google Play app (default language and contact
/// details), offline-first. Read-only.
///
/// The live read opens a temporary Play edit (see `GooglePlayAppDetailsFetching`);
/// `GooglePlayAppSectionLoader` runs it once per screen, or on pull to refresh —
/// never on init or from another screen. The cached result also gives the
/// Store Listings section its default language.
@MainActor
final class GooglePlayAppInfoViewModel: GooglePlayAppInfoViewModelProtocol, GooglePlayAppSectionHosting {

    typealias ConnectionFactory = (GooglePlayCredentials) -> any GooglePlayAppDetailsFetching

    @Published var uiState: GooglePlayAppInfoUiState

    private let loader: GooglePlayAppSectionLoader<GooglePlayAppDetailsCache, any GooglePlayAppDetailsFetching>

    init(
        app: GooglePlayAppItem,
        account: AccountModel,
        keychain: KeyStorable = KeychainStorable.shared,
        storage: PersistentStorable? = nil,
        connectionFactory: @escaping ConnectionFactory = { GooglePlayAccountConnection(credentials: $0) }
    ) {
        self.uiState = GooglePlayAppInfoUiState(account: account, app: app)
        self.loader = GooglePlayAppSectionLoader(
            account: account,
            app: app,
            logTag: "GooglePlayAppInfo",
            keychain: keychain,
            storage: storage ?? SwiftDataStorable.shared,
            connectionFactory: connectionFactory,
            fetch: { connection, packageName in
                try await connection.fetchAppDetails(packageName: packageName)
            }
        )
    }

    func loadIfNeeded() async {
        await loader.loadIfNeeded(into: self)
    }

    func load() async {
        await loader.load(into: self)
    }
}
