import Foundation

/// Why the New Release sheet opened.
struct GooglePlayNewReleaseRequest: Identifiable, Hashable {

    enum Source: Hashable {
        /// A new release from an uploaded bundle, optionally on a given track.
        case bundle(track: String?)
        /// Copy `release` of `fromTrack` to another track.
        case promote(fromTrack: String, release: GooglePlayReleaseModel)
    }

    let id = UUID()
    let source: Source

    var isPromotion: Bool {
        if case .promote = source { return true }
        return false
    }
}

// MARK: - Protocol

@MainActor
protocol GooglePlayNewReleaseViewModelProtocol: ObservableObject {
    var uiState: GooglePlayNewReleaseUiState { get set }
    func selectTrack(_ track: String)
    func selectBundle(_ bundle: GooglePlayBundleModel)
    /// Lists uploaded bundles (a temporary Play edit), once per sheet.
    func loadBundles() async
    /// The write to confirm in the checklist, `nil` while something is missing.
    func pendingWrite() -> GooglePlayPendingWrite?
}

// MARK: - UiState

struct GooglePlayNewReleaseUiState {

    struct TrackOption: Identifiable, Hashable {
        let track: String
        let name: String
        /// "Live: 4.2.0 at 20%", "Draft: 4.3.0 (4305)", "No releases".
        let hint: String
        var id: String { track }
    }

    let request: GooglePlayNewReleaseRequest
    var trackOptions: [TrackOption] = []
    var track: String
    var bundle: GooglePlayBundleModel?
    var bundles: [GooglePlayBundleModel] = []
    var isLoadingBundles = false
    var bundlesError: String?

    var name = ""
    /// Languages in display order (default first) and their notes.
    var languages: [String] = []
    var notes: [String: String] = [:]
    /// Release the notes were copied from ("4.2.0").
    var notesCopiedFrom: String?
    var priority: Int?
    var isDraft = false
    /// 1...99 for a staged rollout, 100 for every user.
    var rolloutPercent = 100

    /// Highest version code live on the chosen track (other releases).
    var liveVersionCode: Int64?

    var trackKind: GooglePlayTrackKind { GooglePlayTrackKind(track: track) }
    var supportsStagedRollout: Bool { GooglePlayReleaseActions.supportsStagedRollout(trackKind) }

    var versionCodes: [String] {
        switch request.source {
        case .promote(_, let release): return release.versionCodes
        case .bundle:                  return bundle.map { [$0.versionCode] } ?? []
        }
    }

    var highestVersionCode: Int64? {
        versionCodes.compactMap(Int64.init).max()
    }

    /// The guard of plan T6: Google refuses a version code that isn't higher
    /// than the one the track already serves.
    var versionCodeError: String? {
        guard let highest = highestVersionCode, let live = liveVersionCode, highest <= live else { return nil }
        return String(localized: "Version code \(String(highest)) isn't higher than \(String(live)), already live on \(trackKind.displayName).",
                      comment: "Google Play new release guard. Arguments: chosen version code, live version code, track name.")
    }

    var status: GooglePlayNewReleaseStatus {
        if isDraft { return .draft }
        if supportsStagedRollout, rolloutPercent < 100 { return .inProgress(userFraction: Double(rolloutPercent) / 100) }
        return .completed
    }

    var releaseNotes: [GooglePlayLocalizedTextModel] {
        languages.compactMap { language in
            let text = (notes[language] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : GooglePlayLocalizedTextModel(language: language, text: text)
        }
    }

    var canContinue: Bool {
        !versionCodes.isEmpty && versionCodeError == nil
            && !notes.values.contains { $0.count > GooglePlayReleaseDetailUiState.releaseNotesLimit }
    }
}

// MARK: - Implementation

/// New Release / Promote (prototype screen 5): track, source (an uploaded
/// bundle, or the release being promoted), name, priority, release notes per
/// language (pre-filled from the newest release of the chosen track), draft
/// and rollout. "Next" hands the change to the Review Checklist.
@MainActor
final class GooglePlayNewReleaseViewModel: GooglePlayNewReleaseViewModelProtocol {

    typealias BundlesLoader = @MainActor () async throws -> [GooglePlayBundleModel]

    @Published var uiState: GooglePlayNewReleaseUiState

    private let tracks: [GooglePlayTrackModel]
    private let listingLanguages: [String]
    private let loadBundlesFromPlay: BundlesLoader
    /// How the account calls Google Play: picks the error copy.
    private let authMethod: AccountAuthMethod
    private var notesEdited = false

    static let standardTracks = ["production", "beta", "alpha", "internal"]

    init(
        request: GooglePlayNewReleaseRequest,
        tracks: [GooglePlayTrackModel],
        listingLanguages: [String],
        loadBundles: @escaping BundlesLoader,
        authMethod: AccountAuthMethod = .keyFile
    ) {
        self.tracks = tracks
        self.listingLanguages = listingLanguages
        self.loadBundlesFromPlay = loadBundles
        self.authMethod = authMethod

        let custom = tracks.map(\.track).filter { !Self.standardTracks.contains($0) }.sorted()
        var names = Self.standardTracks + custom
        let initialTrack: String
        switch request.source {
        case .bundle(let track):
            initialTrack = track ?? "production"
        case .promote(let fromTrack, _):
            names.removeAll { $0 == fromTrack }
            // The track above the source by default (internal → closed → open → production).
            let order = ["internal", "alpha", "beta", "production"]
            let next = order.firstIndex(of: fromTrack).flatMap { order.indices.contains($0 + 1) ? order[$0 + 1] : nil }
            initialTrack = next ?? names.first ?? "production"
        }
        uiState = GooglePlayNewReleaseUiState(request: request, track: initialTrack)
        uiState.trackOptions = names.map { track in
            .init(track: track, name: GooglePlayTrackKind(track: track).displayName, hint: Self.hint(for: tracks.first { $0.track == track }))
        }
        if case .promote(_, let release) = request.source {
            uiState.name = release.name ?? ""
            uiState.priority = release.inAppUpdatePriority
        }
        selectTrack(initialTrack)
    }

    func selectTrack(_ track: String) {
        uiState.track = track
        let cached = tracks.first { $0.track == track }
        uiState.liveVersionCode = GooglePlayReviewChecklist.liveVersionCode(on: cached, excluding: uiState.versionCodes)
        uiState.rolloutPercent = uiState.supportsStagedRollout ? 10 : 100
        if !notesEdited {
            prefillNotes(previous: cached)
        }
    }

    func selectBundle(_ bundle: GooglePlayBundleModel) {
        uiState.bundle = bundle
        selectTrack(uiState.track)
    }

    func loadBundles() async {
        guard uiState.bundles.isEmpty, !uiState.isLoadingBundles else { return }
        uiState.isLoadingBundles = true
        uiState.bundlesError = nil
        defer { uiState.isLoadingBundles = false }
        do {
            uiState.bundles = try await loadBundlesFromPlay()
        } catch {
            uiState.bundlesError = (error as? GooglePlayReleaseWriteError)?.errorDescription
                ?? GooglePlayErrorTranslator.friendlyMessage(for: error, operation: .appContentRead, authMethod: authMethod)
        }
    }

    /// Marks the notes as the user's own, so changing track keeps them.
    func notesChanged() {
        notesEdited = true
    }

    func pendingWrite() -> GooglePlayPendingWrite? {
        let state = uiState
        guard state.canContinue else { return nil }
        let name = state.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = name.isEmpty ? state.versionCodes.joined(separator: ", ") : GooglePlayReleaseNaming.shortName(name: name, versionCodes: state.versionCodes)
        switch state.request.source {
        case .bundle:
            return GooglePlayPendingWrite(
                track: state.track,
                change: .create(GooglePlayNewRelease(
                    versionCodes: state.versionCodes,
                    name: name.isEmpty ? nil : name,
                    releaseNotes: state.releaseNotes,
                    status: state.status,
                    inAppUpdatePriority: state.priority
                )),
                releaseTitle: title
            )
        case .promote(let fromTrack, let release):
            return GooglePlayPendingWrite(
                track: state.track,
                change: .promote(
                    fromTrack: fromTrack,
                    versionCodes: release.versionCodes,
                    status: state.status,
                    name: name.isEmpty ? nil : name,
                    releaseNotes: state.releaseNotes,
                    inAppUpdatePriority: state.priority
                ),
                releaseTitle: title,
                release: release
            )
        }
    }

    // MARK: - Private

    /// Notes of the promoted release, or of the newest release on the track
    /// ("Copied from 4.2.0"); otherwise empty notes in the listing languages.
    private func prefillNotes(previous track: GooglePlayTrackModel?) {
        let source: GooglePlayReleaseModel?
        if case .promote(_, let release) = uiState.request.source {
            source = release
        } else {
            source = track?.releases
                .filter { !$0.releaseNotes.isEmpty }
                .max { ($0.versionCodes.compactMap(Int64.init).max() ?? 0) < ($1.versionCodes.compactMap(Int64.init).max() ?? 0) }
        }
        let copied = source?.releaseNotes ?? []
        var languages = copied.map(\.language)
        for language in listingLanguages where !languages.contains(language) {
            languages.append(language)
        }
        if languages.isEmpty { languages = ["en-US"] }
        uiState.languages = languages
        uiState.notes = Dictionary(copied.map { ($0.language, $0.text) }, uniquingKeysWith: { first, _ in first })
        uiState.notesCopiedFrom = copied.isEmpty ? nil : source?.shortName
    }

    private static func hint(for track: GooglePlayTrackModel?) -> String {
        guard let releases = track?.releases, !releases.isEmpty else { return String(localized: "No releases") }
        // A draft newer than what is served is what the track is about to get.
        let newest = releases.max { ($0.versionCodes.compactMap(Int64.init).max() ?? 0) < ($1.versionCodes.compactMap(Int64.init).max() ?? 0) }
        if let newest, newest.status == .draft {
            return String(localized: "Draft: \(newest.displayName)", comment: "Google Play track hint. Argument: release name.")
        }
        if let live = releases.first(where: { $0.status == .inProgress || $0.status == .halted }) {
            return String(localized: "Live: \(live.shortName) at \(GooglePlayPendingWrite.percent(live.userFraction ?? 0))",
                          comment: "Google Play track hint. Arguments: release name, rollout percentage.")
        }
        if let live = releases.first(where: { $0.status == .completed }) {
            return String(localized: "Live: \(live.shortName)", comment: "Google Play track hint. Argument: release name.")
        }
        if let draft = releases.first(where: { $0.status == .draft }) {
            return String(localized: "Draft: \(draft.displayName)", comment: "Google Play track hint. Argument: release name.")
        }
        return String(localized: "No releases")
    }
}
