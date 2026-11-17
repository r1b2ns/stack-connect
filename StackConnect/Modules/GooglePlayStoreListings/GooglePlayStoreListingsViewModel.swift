import Foundation

// MARK: - Protocol

@MainActor
protocol GooglePlayStoreListingsViewModelProtocol: ObservableObject {
    var uiState: GooglePlayStoreListingsUiState { get set }
    /// Loads once per screen: coming back from a language doesn't read again.
    func loadIfNeeded() async
    /// Reads again (pull to refresh, Retry).
    func load() async
}

// MARK: - UiState

struct GooglePlayStoreListingsUiState: GooglePlayAppSectionUiState {
    var account: AccountModel
    var app: GooglePlayAppItem
    var section = GooglePlayAppSectionState<[GooglePlayStoreListingModel]>()
    /// Default language from the cached App Details, if any (listed first).
    var defaultLanguage: String?

    /// `nil` until loaded (cache or API); empty when the app has no listing.
    var listings: [GooglePlayStoreListingModel]? {
        section.content
    }
}

// MARK: - Implementation

/// Store listings of a Google Play app, offline-first. Read-only.
///
/// The live read opens a temporary Play edit (see `GooglePlayStoreListingsFetching`);
/// `GooglePlayAppSectionLoader` runs it once per screen, or on pull to refresh —
/// never on init or from another screen.
@MainActor
final class GooglePlayStoreListingsViewModel: GooglePlayStoreListingsViewModelProtocol, GooglePlayAppSectionHosting {

    typealias ConnectionFactory = (GooglePlayCredentials) -> any GooglePlayStoreListingsFetching

    @Published var uiState: GooglePlayStoreListingsUiState

    private let detailsCache: GooglePlayAppCacheStore<GooglePlayAppDetailsCache>
    private let loader: GooglePlayAppSectionLoader<GooglePlayStoreListingsCache, any GooglePlayStoreListingsFetching>

    init(
        app: GooglePlayAppItem,
        account: AccountModel,
        keychain: KeyStorable = KeychainStorable.shared,
        storage: PersistentStorable? = nil,
        connectionFactory: @escaping ConnectionFactory = { GooglePlayAccountConnection(credentials: $0) }
    ) {
        let storage: PersistentStorable = storage ?? SwiftDataStorable.shared
        self.uiState = GooglePlayStoreListingsUiState(account: account, app: app)
        self.detailsCache = GooglePlayAppCacheStore(storage: storage, accountId: account.id, packageName: app.packageName)
        self.loader = GooglePlayAppSectionLoader(
            account: account,
            app: app,
            logTag: "GooglePlayStoreListings",
            keychain: keychain,
            storage: storage,
            connectionFactory: connectionFactory,
            fetch: { connection, packageName in
                try await connection.fetchStoreListings(packageName: packageName)
            }
        )
    }

    func loadIfNeeded() async {
        await loader.loadIfNeeded(into: self)
    }

    func load() async {
        await loader.load(into: self)
    }

    // MARK: - GooglePlayAppSectionHosting

    /// The default language comes from the cached App Details (never a live read).
    func prepareLoad() async {
        uiState.defaultLanguage = await detailsCache.load()?.details.defaultLanguage
    }

    /// Default language first, then by language name.
    func present(_ content: [GooglePlayStoreListingModel]) -> [GooglePlayStoreListingModel] {
        GooglePlayStoreListingModel.sorted(content, defaultLanguage: uiState.defaultLanguage)
    }
}
