import Foundation

// MARK: - Protocol

@MainActor
protocol GooglePlayTracksViewModelProtocol: ObservableObject {
    var uiState: GooglePlayTracksUiState { get set }
    /// Loads once per screen: coming back from a release doesn't read again.
    func loadIfNeeded() async
    /// Reads again (pull to refresh, Retry).
    func load() async
}

// MARK: - UiState

struct GooglePlayTracksUiState: GooglePlayAppSectionUiState {
    var account: AccountModel
    var app: GooglePlayAppItem
    var section = GooglePlayAppSectionState<[GooglePlayTrackModel]>()

    /// `nil` until loaded (cache or API). Sorted production → testing → custom.
    var tracks: [GooglePlayTrackModel]? {
        section.content
    }
}

// MARK: - Implementation

/// Release tracks of a Google Play app, offline-first. Read-only.
///
/// The live read opens a temporary Play edit (see `GooglePlayTracksFetching`);
/// `GooglePlayAppSectionLoader` runs it once per screen, or on pull to refresh —
/// never on init or from another screen.
@MainActor
final class GooglePlayTracksViewModel: GooglePlayTracksViewModelProtocol, GooglePlayAppSectionHosting {

    typealias ConnectionFactory = (GooglePlayCredentials) -> any GooglePlayTracksFetching

    @Published var uiState: GooglePlayTracksUiState

    private let loader: GooglePlayAppSectionLoader<GooglePlayTracksCache, any GooglePlayTracksFetching>

    init(
        app: GooglePlayAppItem,
        account: AccountModel,
        keychain: KeyStorable = KeychainStorable.shared,
        storage: PersistentStorable? = nil,
        connectionFactory: @escaping ConnectionFactory = { GooglePlayAccountConnection(credentials: $0) }
    ) {
        self.uiState = GooglePlayTracksUiState(account: account, app: app)
        self.loader = GooglePlayAppSectionLoader(
            account: account,
            app: app,
            logTag: "GooglePlayTracks",
            keychain: keychain,
            storage: storage ?? SwiftDataStorable.shared,
            connectionFactory: connectionFactory,
            fetch: { connection, packageName in
                try await connection.fetchTracks(packageName: packageName)
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

    func present(_ content: [GooglePlayTrackModel]) -> [GooglePlayTrackModel] {
        GooglePlayTrackModel.sorted(content)
    }
}
