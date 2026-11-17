import Foundation

// MARK: - State

/// What an edit-based Google Play section shows, offline-first: its content
/// (cached, then live), the load flags and the last failure.
struct GooglePlayAppSectionState<Content> {
    /// `nil` until loaded (cache or API).
    var content: Content?
    /// Nothing is cached while the live read runs (full-screen spinner).
    var isLoading = false
    /// A load is in flight. This is the loader's in-flight guard: while it is
    /// true no second load starts, so a refresh never opens a second Play edit.
    var isSyncing = false
    /// Cached content is on screen while the live read runs.
    var showSyncToast = false
    /// Last failure, already user-facing. Full screen when nothing is cached,
    /// inline above the cached content otherwise.
    var error: String?

    var hasContent: Bool {
        content != nil
    }
}

/// UiState of an edit-based section screen: the shared `section` state, plus
/// flat accessors for the views.
protocol GooglePlayAppSectionUiState {
    associatedtype Content
    var section: GooglePlayAppSectionState<Content> { get set }
}

extension GooglePlayAppSectionUiState {
    var isLoading: Bool { section.isLoading }
    var isSyncing: Bool { section.isSyncing }
    var error: String? { section.error }
    var hasContent: Bool { section.hasContent }

    /// Writable so the sync toast can dismiss itself.
    var showSyncToast: Bool {
        get { section.showSyncToast }
        set { section.showSyncToast = newValue }
    }
}

/// A ViewModel whose section `GooglePlayAppSectionLoader` loads: the loader
/// writes `uiState.section` and calls the optional hooks.
@MainActor
protocol GooglePlayAppSectionHosting: AnyObject, Sendable {
    associatedtype UiState: GooglePlayAppSectionUiState
    var uiState: UiState { get set }

    /// Runs after the access check, before the cache is read — e.g. to read
    /// other cached data the content is presented with.
    func prepareLoad() async

    /// The content as shown (e.g. sorted). Applied to cached and live content;
    /// the cache keeps what the API returned.
    func present(_ content: UiState.Content) -> UiState.Content
}

extension GooglePlayAppSectionHosting {
    func prepareLoad() async {}

    func present(_ content: UiState.Content) -> UiState.Content {
        content
    }
}

// MARK: - Loader

/// Loads one edit-based section of a Google Play app — store listings, tracks
/// or app details — for its ViewModel. Everything the three sections share
/// lives here (D14, D16, D17):
///
/// 1. access: the per-app scope and the section's view rule
///    (`GooglePlayAppSectionAccess`), re-checked before every read;
/// 2. cache first, with a spinner only while nothing is cached;
/// 3. the credentials guard;
/// 4. the live read through a temporary Play edit, saved to the cache;
/// 5. user-facing errors (offline with a cache stays silent).
///
/// **Once per screen (D14).** The screen's `.task` calls `loadIfNeeded()`,
/// which reads once per ViewModel: SwiftUI cancels a `.task` when a child
/// screen is pushed and starts it again on the way back, and that must not
/// open another edit. `load()` (pull to refresh, Retry) always reads.
///
/// **One edit at a time.** A load runs in a task the loader owns, so leaving
/// the screen can't cut it short half-way (the Rust core keeps running a
/// cancelled call anyway), and `load()` while one is in flight waits for it
/// instead of starting another. The connection is built once per loader, so
/// every read of the screen goes through the same core provider, whose edit
/// lock serialises the edit sessions it opens.
@MainActor
final class GooglePlayAppSectionLoader<Entry: GooglePlayAppSectionCache, Connection: Sendable> {

    typealias Content = Entry.Content
    typealias ConnectionFactory = (GooglePlayCredentials) -> Connection
    typealias Fetch = @Sendable (_ connection: Connection, _ packageName: String) async throws -> Content

    private let account: AccountModel
    private let app: GooglePlayAppItem
    private let resource: AccountRuleResource
    /// Log prefix, e.g. `GooglePlayTracks`.
    private let logTag: String
    private let keychain: KeyStorable
    private let cache: GooglePlayAppCacheStore<Entry>
    private let connectionFactory: ConnectionFactory
    private let fetch: Fetch

    /// Built on the first live read, then reused for every later one.
    private var connection: Connection?
    private var hasLoaded = false
    private var inFlight: Task<Void, Never>?

    /// - Parameters:
    ///   - resource: account rule needed to view the section.
    ///   - fetch: the section's live (edit-based) read.
    init(
        account: AccountModel,
        app: GooglePlayAppItem,
        resource: AccountRuleResource = .apps,
        logTag: String,
        keychain: KeyStorable,
        storage: PersistentStorable,
        connectionFactory: @escaping ConnectionFactory,
        fetch: @escaping Fetch
    ) {
        self.account = account
        self.app = app
        self.resource = resource
        self.logTag = logTag
        self.keychain = keychain
        self.cache = GooglePlayAppCacheStore(storage: storage, accountId: account.id, packageName: app.packageName)
        self.connectionFactory = connectionFactory
        self.fetch = fetch
    }

    /// Loads unless this loader already did (or is doing it). What a screen
    /// runs when it appears.
    func loadIfNeeded<Host: GooglePlayAppSectionHosting>(into host: Host) async
    where Host.UiState.Content == Content {
        guard !hasLoaded else { return }
        await load(into: host)
    }

    /// Loads again (pull to refresh, Retry). While a load is in flight it waits
    /// for that one instead of opening a second Play edit.
    func load<Host: GooglePlayAppSectionHosting>(into host: Host) async
    where Host.UiState.Content == Content {
        if host.uiState.section.isSyncing {
            await inFlight?.value
            return
        }

        hasLoaded = true
        host.uiState.section.isSyncing = true
        // Unstructured, so the caller's cancellation (the screen's `.task`)
        // doesn't reach it.
        let task = Task {
            await self.performLoad(into: host)
            host.uiState.section.isSyncing = false
            self.inFlight = nil
        }
        inFlight = task
        await task.value
    }

    // MARK: - Private

    private func performLoad<Host: GooglePlayAppSectionHosting>(into host: Host) async
    where Host.UiState.Content == Content {
        host.uiState.section.error = nil

        // Defense in depth (D16): the menu checks this too, but a denied section
        // must never open an edit.
        if let denial = GooglePlayAppSectionAccess.denialMessage(account: account, app: app, resource: resource) {
            host.uiState.section.error = denial
            return
        }

        await host.prepareLoad()

        // 1. Cache first (offline-first).
        if let cached = await cache.load() {
            host.uiState.section.content = host.present(cached.content)
        }
        host.uiState.section.isLoading = !host.uiState.section.hasContent

        guard let connection = liveConnection() else {
            Log.print.error("[\(self.logTag)] No credentials found for account: \(self.account.name)")
            host.uiState.section.error = String(localized: "No credentials found for this account.")
            host.uiState.section.isLoading = false
            return
        }

        // 2. Live read (temporary Play edit, D14).
        host.uiState.section.showSyncToast = host.uiState.section.hasContent

        do {
            let content = try await fetch(connection, app.packageName)
            host.uiState.section.content = host.present(content)
            await cache.save(Entry(accountId: account.id, packageName: app.packageName, content: content))
            Log.print.info("[\(self.logTag)] Synced \(self.app.packageName)")
        } catch {
            Log.print.error("[\(self.logTag)] Sync failed: \(error.localizedDescription)")
            // Offline with cached content: the global offline banner already
            // says so — keep the content without a second warning.
            if !(GooglePlayErrorTranslator.isOffline(error) && host.uiState.section.hasContent) {
                host.uiState.section.error = GooglePlayErrorTranslator.friendlyMessage(for: error, operation: .appContentRead)
            }
        }

        host.uiState.section.isLoading = false
    }

    /// The connection for live reads, built once from the stored credentials;
    /// `nil` when the account has none.
    private func liveConnection() -> Connection? {
        if let connection {
            return connection
        }
        guard let credentials: GooglePlayCredentials = keychain.object(forKey: "credentials.\(account.id)") else {
            return nil
        }
        let connection = connectionFactory(credentials)
        self.connection = connection
        return connection
    }
}
