import SwiftUI

// MARK: - Factory

@MainActor
struct GooglePlayReleaseDetailViewFactory {
    static func build(app: GooglePlayAppItem, account: AccountModel, track: String, release: GooglePlayReleaseModel) -> some View {
        GooglePlayReleaseDetailEntry(app: app, account: account, track: track, release: release)
    }
}

// MARK: - Entry

private struct GooglePlayReleaseDetailEntry: View {

    @StateObject private var viewModel: GooglePlayReleaseDetailViewModel
    @StateObject private var writes: GooglePlayReleaseWriteViewModel

    init(app: GooglePlayAppItem, account: AccountModel, track: String, release: GooglePlayReleaseModel) {
        _viewModel = StateObject(wrappedValue: GooglePlayReleaseDetailViewModel(app: app, account: account, track: track, release: release))
        _writes = StateObject(wrappedValue: GooglePlayReleaseWriteViewModel(app: app, account: account))
    }

    var body: some View {
        GooglePlayReleaseDetailView(viewModel: viewModel, writes: writes)
    }
}

// MARK: - View

/// One release of a Google Play track (prototype screen 3): header, build,
/// content (name, priority, release notes — editable with the writes flag and
/// the `version` edit rule), rollout, country targeting, what only Play Console
/// offers, and a bottom bar driven by `GooglePlayReleaseActions`.
struct GooglePlayReleaseDetailView<ViewModel: GooglePlayReleaseDetailViewModelProtocol, Writes: GooglePlayReleaseWriteViewModelProtocol>: View {

    @ObservedObject var viewModel: ViewModel
    @ObservedObject var writes: Writes

    private var state: GooglePlayReleaseDetailUiState { viewModel.uiState }

    var body: some View {
        List {
            if let release = state.release {
                buildHeaderSection(release)
                buildBuildSection(release)
                buildContentSection(release)
                buildReleaseNotesSections(release)
                buildRolloutSection(release)
                buildActionsSection(release)
                buildPlayConsoleSection()
            }
        }
        .navigationTitle(state.release?.shortName ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { buildToolbar() }
        // Before the bar, so the toast sits above it.
        .googlePlayReleaseWrites(writes)
        .safeAreaInset(edge: .bottom) {
            if !state.hasChanges, let release = state.release {
                GooglePlayReleaseActionBar(actions: state.actions.filter { $0 != .promote }, isBusy: writes.uiState.isWriting) { action in
                    writes.start(action, release: release, track: state.track)
                }
            }
        }
        .task {
            await viewModel.load()
            await writes.loadContext()
        }
        .onChange(of: writes.uiState.revision) {
            Task {
                await viewModel.load()
                await writes.loadContext()
            }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private func buildToolbar() -> some ToolbarContent {
        if state.hasChanges {
            ToolbarItem(placement: .cancellationAction) {
                Button(String(localized: "Discard")) { viewModel.discardChanges() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(String(localized: "Save")) {
                    if let write = viewModel.metadataWrite() {
                        writes.request(write)
                    }
                }
                .fontWeight(.semibold)
                .disabled(writes.uiState.isWriting)
            }
        }
    }

    // MARK: - Header

    private func buildHeaderSection(_ release: GooglePlayReleaseModel) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(state.trackKind.displayName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    HStack(spacing: 6) {
                        Circle()
                            .fill(release.status.color)
                            .frame(width: 8, height: 8)
                        Text(release.status.displayName)
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                    .accessibilityElement(children: .combine)
                }
                Text(release.shortName)
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
                if let lifecycle = state.lifecycleState {
                    Text("Review status: \(lifecycle.displayName)",
                         comment: "Google Play release header. Argument: the release lifecycle state, e.g. Published.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Build

    private func buildBuildSection(_ release: GooglePlayReleaseModel) -> some View {
        Section {
            StackSubtitleRow(
                icon: "shippingbox.fill",
                iconColor: .gray,
                title: String(localized: "App Bundle"),
                subtitle: versionCodesText(release.versionCodes),
                showsChevron: false
            )
        } header: {
            Text("Build")
        }
    }

    // MARK: - Content

    @ViewBuilder
    private func buildContentSection(_ release: GooglePlayReleaseModel) -> some View {
        Section {
            if state.canEditMetadata {
                LabeledContent(String(localized: "Release Name")) {
                    TextField(String(localized: "Release Name"), text: draftBinding(\.name, default: ""))
                        .multilineTextAlignment(.trailing)
                        .submitLabel(.done)
                }
            } else {
                LabeledContent(String(localized: "Release Name"), value: release.name ?? "–")
            }

            StackSubtitleRow(
                icon: "sparkles",
                iconColor: .orange,
                title: String(localized: "Release Notes"),
                subtitle: notesSummary(release),
                showsChevron: false
            )

            if state.canEditMetadata {
                Picker(String(localized: "In-App Update Priority"), selection: draftBinding(\.priority, default: nil)) {
                    Text("Not set").tag(Int?.none)
                    ForEach(0...5, id: \.self) { value in
                        Text("\(value) of 5").tag(Int?.some(value))
                    }
                }
            } else {
                LabeledContent(String(localized: "In-App Update Priority"),
                               value: release.inAppUpdatePriority.map { String(localized: "\($0) of 5") } ?? String(localized: "Not set"))
            }
        } header: {
            Text("Content")
        }
    }

    @ViewBuilder
    private func buildReleaseNotesSections(_ release: GooglePlayReleaseModel) -> some View {
        let languages = state.draft?.languages ?? release.releaseNotes.map(\.language)
        ForEach(languages, id: \.self) { language in
            Section {
                if state.canEditMetadata {
                    let text = state.draft?.notes[language] ?? ""
                    TextEditor(text: noteBinding(language))
                        .frame(minHeight: 88)
                        .accessibilityLabel(Text("Release notes in \(GooglePlayLanguage.displayName(for: language))"))
                    Text("\(text.count) / \(GooglePlayReleaseDetailUiState.releaseNotesLimit)")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(text.count > GooglePlayReleaseDetailUiState.releaseNotesLimit ? .red : .secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                } else {
                    let text = release.releaseNotes.first { $0.language == language }?.text ?? ""
                    HStack(alignment: .top) {
                        Text(text)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        CopyButton(text: text)
                    }
                }
            } header: {
                Text("Release Notes – \(GooglePlayLanguage.displayName(for: language))")
            }
        }
    }

    // MARK: - Rollout

    /// The rollout row opens the Staged Rollout sheet whenever the bar offers
    /// a rollout change (prototype screens 3 → 4).
    private var opensRolloutSheet: Bool {
        !state.actions.filter { [.rollOut, .increaseRollout, .halt, .resume].contains($0) }.isEmpty
    }

    private func buildRolloutSection(_ release: GooglePlayReleaseModel) -> some View {
        Section {
            Button {
                writes.openRollout(release: release, track: state.track)
            } label: {
                StackSubtitleRow(
                    icon: "chart.bar.fill",
                    iconColor: .teal,
                    title: String(localized: "Staged Rollout"),
                    subtitle: rolloutText(release),
                    progress: release.rolloutFraction,
                    progressTint: release.status == .halted ? .orange : .teal,
                    showsChevron: opensRolloutSheet
                )
            }
            .disabled(!opensRolloutSheet)
            .foregroundStyle(.primary)

            StackSubtitleRow(
                icon: "globe",
                iconColor: .blue,
                title: String(localized: "Country Targeting"),
                subtitle: countryText(release.countryTargeting),
                showsChevron: false
            )
        } header: {
            Text("Rollout")
        } footer: {
            Text("Country targeting applies only while the release is rolling out. It can be changed in Play Console.")
        }
    }

    // MARK: - Play Console

    @ViewBuilder
    private func buildActionsSection(_ release: GooglePlayReleaseModel) -> some View {
        if state.actions.contains(.promote) {
            Section {
                Button {
                    writes.start(.promote, release: release, track: state.track)
                } label: {
                    StackSubtitleRow(icon: "arrow.up", iconColor: .green, title: String(localized: "Promote to Another Track"))
                }
                .foregroundStyle(.primary)
            } header: {
                Text("Actions")
            }
        }
    }

    private func buildPlayConsoleSection() -> some View {
        Section {
            if let url = URL(string: "https://play.google.com/console") {
                Link(String(localized: "Open Play Console"), destination: url)
            }
        } header: {
            Text("Only in Play Console")
        } footer: {
            Text("Rejection reasons and review history aren't shared by the Google Play API. Open Play Console for policy details.")
        }
    }

    // MARK: - Text

    private func versionCodesText(_ codes: [String]) -> String {
        switch codes.count {
        case 0:  return "–"
        case 1:  return String(localized: "Version code \(codes[0])")
        default: return String(localized: "Version codes \(codes.joined(separator: ", "))")
        }
    }

    private func notesSummary(_ release: GooglePlayReleaseModel) -> String {
        let count = state.draft?.languages.count ?? release.releaseNotes.count
        guard count > 0 else { return String(localized: "No release notes") }
        if count == 1 {
            return String(localized: "1 language · \(GooglePlayReleaseDetailUiState.releaseNotesLimit) characters",
                          comment: "Google Play release notes summary. Argument: character limit.")
        }
        return String(localized: "\(count) languages · \(GooglePlayReleaseDetailUiState.releaseNotesLimit) characters each",
                      comment: "Google Play release notes summary. Arguments: number of languages, character limit.")
    }

    private func rolloutText(_ release: GooglePlayReleaseModel) -> String {
        if let fraction = release.rolloutFraction {
            let percent = GooglePlayPendingWrite.percent(fraction)
            return release.status == .halted
                ? String(localized: "Halted at \(percent) of users", comment: "Argument: a percentage.")
                : String(localized: "\(percent) of users", comment: "Argument: a percentage.")
        }
        switch release.status {
        case .completed: return String(localized: "All users")
        case .draft:     return String(localized: "Not rolled out yet")
        default:         return "–"
        }
    }

    private func countryText(_ targeting: GooglePlayCountryTargetingModel?) -> String {
        guard let targeting, !targeting.countries.isEmpty else { return String(localized: "All countries") }
        let count = targeting.countries.count
        return targeting.includeRestOfWorld
            ? String(localized: "\(count) countries + rest of world", comment: "Argument: number of countries.")
            : String(localized: "\(count) countries", comment: "Argument: number of countries.")
    }

    // MARK: - Bindings

    private func draftBinding<Value>(_ keyPath: WritableKeyPath<GooglePlayReleaseMetadataDraft, Value>, default value: Value) -> Binding<Value> {
        Binding(
            get: { viewModel.uiState.draft?[keyPath: keyPath] ?? value },
            set: { viewModel.uiState.draft?[keyPath: keyPath] = $0 }
        )
    }

    private func noteBinding(_ language: String) -> Binding<String> {
        Binding(
            get: { viewModel.uiState.draft?.notes[language] ?? "" },
            set: { viewModel.uiState.draft?.notes[language] = $0 }
        )
    }
}
