import Foundation

// MARK: - Protocol

@MainActor
protocol GooglePlayReleaseDetailViewModelProtocol: ObservableObject {
    var uiState: GooglePlayReleaseDetailUiState { get set }
    /// Reads the release from the local caches only (never a Play edit).
    func load() async
    /// The metadata change for the edited fields, `nil` when nothing changed.
    func metadataWrite() -> GooglePlayPendingWrite?
    /// Puts the edited fields back to the release's values.
    func discardChanges()
}

// MARK: - UiState

/// Editable copy of a release's metadata.
struct GooglePlayReleaseMetadataDraft: Equatable {
    var name: String
    /// Language → text, in the release's language order (`languages`).
    var notes: [String: String]
    var languages: [String]
    var priority: Int?

    init(release: GooglePlayReleaseModel) {
        name = release.name ?? ""
        languages = release.releaseNotes.map(\.language)
        notes = Dictionary(release.releaseNotes.map { ($0.language, $0.text) }, uniquingKeysWith: { first, _ in first })
        priority = release.inAppUpdatePriority
    }

    var releaseNotes: [GooglePlayLocalizedTextModel] {
        languages.map { GooglePlayLocalizedTextModel(language: $0, text: notes[$0] ?? "") }
    }
}

struct GooglePlayReleaseDetailUiState {
    var account: AccountModel
    var app: GooglePlayAppItem
    /// Raw track name.
    let track: String
    let releaseKey: GooglePlayReleaseKey
    /// `nil` when the release is not in the tracks cache any more.
    var release: GooglePlayReleaseModel?
    /// From the edit-free summaries, when they hold this release.
    var lifecycleState: GooglePlayReleaseLifecycleState?
    /// What the bottom bar and swipe actions offer (plan R8).
    var actions: [GooglePlayReleaseAction] = []
    /// Name, notes and priority are editable (flag + `canEdit(.version)`).
    var canEditMetadata = false
    var draft: GooglePlayReleaseMetadataDraft?

    var trackKind: GooglePlayTrackKind { GooglePlayTrackKind(track: track) }

    var hasChanges: Bool {
        guard let release, let draft else { return false }
        return draft != GooglePlayReleaseMetadataDraft(release: release)
    }

    /// Google limits release notes to 500 characters per language.
    static let releaseNotesLimit = 500
}

// MARK: - Implementation

/// One release of a Google Play track (prototype screen 3). Reads the caches
/// only; every change goes through the shared write flow
/// (`GooglePlayReleaseWriteViewModel`), after which the screen loads again.
@MainActor
final class GooglePlayReleaseDetailViewModel: GooglePlayReleaseDetailViewModelProtocol {

    @Published var uiState: GooglePlayReleaseDetailUiState

    private let storage: PersistentStorable
    private let featureFlags: FeatureFlags

    init(
        app: GooglePlayAppItem,
        account: AccountModel,
        track: String,
        release: GooglePlayReleaseModel,
        storage: PersistentStorable? = nil,
        featureFlags: FeatureFlags = .shared
    ) {
        self.uiState = GooglePlayReleaseDetailUiState(
            account: account,
            app: app,
            track: track,
            releaseKey: release.releaseKey(track: track),
            release: release
        )
        self.storage = storage ?? SwiftDataStorable.shared
        self.featureFlags = featureFlags
        apply(release: release, lifecycleState: nil)
    }

    func load() async {
        let accountId = uiState.account.id
        let packageName = uiState.app.packageName
        let tracks = await GooglePlayAppCacheStore<GooglePlayTracksCache>(
            storage: storage, accountId: accountId, packageName: packageName
        ).load()
        let summaries = await GooglePlayAppCacheStore<GooglePlayReleaseSummariesCache>(
            storage: storage, accountId: accountId, packageName: packageName
        ).load()

        let key = uiState.releaseKey
        let release = tracks?.tracks
            .first { $0.track == key.track }?
            .releases.first { $0.releaseKey(track: key.track) == key }
        let lifecycle = summaries?.summaries.first { $0.releaseKey == key }?.lifecycleState

        if let release {
            apply(release: release, lifecycleState: lifecycle)
        } else if tracks != nil {
            // Gone from the track (completed over, replaced): keep showing the
            // last known copy, without actions.
            uiState.lifecycleState = lifecycle
            uiState.actions = []
            uiState.canEditMetadata = false
        }
    }

    func metadataWrite() -> GooglePlayPendingWrite? {
        guard uiState.hasChanges, let release = uiState.release, let draft = uiState.draft else { return nil }
        let original = GooglePlayReleaseMetadataDraft(release: release)
        let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let update = GooglePlayReleaseMetadataUpdate(
            name: draft.name != original.name ? name : nil,
            releaseNotes: draft.notes != original.notes ? draft.releaseNotes : nil,
            inAppUpdatePriority: draft.priority != original.priority ? draft.priority : nil
        )
        return GooglePlayPendingWrite(
            track: uiState.track,
            change: .updateMetadata(versionCodes: release.versionCodes, update: update),
            releaseTitle: release.shortName
        )
    }

    func discardChanges() {
        uiState.draft = uiState.release.map(GooglePlayReleaseMetadataDraft.init)
    }

    // MARK: - Private

    private func apply(release: GooglePlayReleaseModel, lifecycleState: GooglePlayReleaseLifecycleState?) {
        let account = uiState.account
        let app = uiState.app
        uiState.release = release
        uiState.lifecycleState = lifecycleState
        uiState.draft = GooglePlayReleaseMetadataDraft(release: release)
        uiState.canEditMetadata = GooglePlayReleaseWriteAccess.isAllowed(.edit, account: account, app: app, featureFlags: featureFlags)
        uiState.actions = GooglePlayReleaseActions.actions(for: release, on: uiState.trackKind, lifecycleState: lifecycleState)
            .filter { GooglePlayReleaseWriteAccess.isAllowed($0.writeKind, account: account, app: app, featureFlags: featureFlags) }
            .filter { $0 != .promote }
    }
}
