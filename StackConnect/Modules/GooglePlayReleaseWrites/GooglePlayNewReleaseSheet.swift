import SwiftUI

/// New Release / Promote sheet (prototype screen 5). "Next" pushes the Review
/// Checklist, which commits the release.
struct GooglePlayNewReleaseSheet<Writes: GooglePlayReleaseWriteViewModelProtocol>: View {

    @ObservedObject var writes: Writes
    @StateObject private var viewModel: GooglePlayNewReleaseViewModel
    @Environment(\.dismiss) private var dismiss

    init(request: GooglePlayNewReleaseRequest, writes: Writes) {
        self.writes = writes
        _viewModel = StateObject(wrappedValue: GooglePlayNewReleaseViewModel(
            request: request,
            tracks: writes.uiState.cachedTracks,
            listingLanguages: writes.uiState.listingLanguages,
            loadBundles: { try await writes.fetchBundles() },
            authMethod: writes.uiState.authMethod
        ))
    }

    private var state: GooglePlayNewReleaseUiState { viewModel.uiState }

    private var screen: AnalyticsScreen {
        state.request.isPromotion ? .googlePlayPromoteRelease : .googlePlayNewRelease
    }

    var body: some View {
        NavigationStack {
            Form {
                buildTrackSection()
                buildSourceSection()
                buildReleaseSection()
                buildNotesSection()
                buildRolloutSection()
            }
            .navigationTitle(state.request.isPromotion ? String(localized: "Promote Release") : String(localized: "New Release"))
            .navigationBarTitleDisplayMode(.inline)
            .trackScreen(screen)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    StackTrackedButton(String(localized: "Cancel"), button: .cancel, on: screen) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    StackTrackedButton(String(localized: "Next"), button: .next, on: screen) {
                        if let write = viewModel.pendingWrite() {
                            writes.request(write)
                        }
                    }
                    .fontWeight(.semibold)
                    .disabled(!state.canContinue)
                }
            }
            .googlePlayReleaseWrites(writes, inSheet: true)
            .googlePlayReviewChecklistDestination(writes)
            .onChange(of: writes.uiState.revision) { dismiss() }
        }
    }

    // MARK: - Track

    private func buildTrackSection() -> some View {
        Section {
            ForEach(state.trackOptions) { option in
                StackChoiceRow(title: option.name, subtitle: option.hint, isSelected: state.track == option.track) {
                    viewModel.selectTrack(option.track)
                }
            }
        } header: {
            Text("Track")
        }
    }

    // MARK: - Source

    @ViewBuilder
    private func buildSourceSection() -> some View {
        Section {
            if case .promote(let fromTrack, let release) = state.request.source {
                LabeledContent(String(localized: "Promote from"),
                               value: "\(GooglePlayTrackKind(track: fromTrack).displayName) · \(release.displayName)")
            }
            if state.request.isPromotion {
                StackSubtitleRow(
                    icon: "shippingbox.fill",
                    iconColor: .gray,
                    title: String(localized: "App Bundle"),
                    subtitle: versionCodeText,
                    showsChevron: false
                )
            } else {
                NavigationLink {
                    GooglePlayBundlePicker(viewModel: viewModel)
                } label: {
                    StackSubtitleRow(
                        icon: "shippingbox.fill",
                        iconColor: .gray,
                        title: String(localized: "App Bundle"),
                        subtitle: state.bundle == nil ? String(localized: "Choose an uploaded bundle") : versionCodeText,
                        showsChevron: false
                    )
                }
            }
        } header: {
            Text("Source")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                if let error = state.versionCodeError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
                if !state.request.isPromotion {
                    Text("Pick a bundle that was already uploaded to Google Play (by CI or Play Console). Uploading a new .aab from the phone isn't supported.")
                }
            }
        }
    }

    private var versionCodeText: String {
        String(localized: "Version code \(state.versionCodes.joined(separator: ", "))")
    }

    // MARK: - Release

    private func buildReleaseSection() -> some View {
        Section {
            LabeledContent(String(localized: "Release Name")) {
                TextField(String(localized: "Release Name"), text: $viewModel.uiState.name)
                    .multilineTextAlignment(.trailing)
                    .submitLabel(.done)
            }
            Picker(String(localized: "In-App Update Priority"), selection: $viewModel.uiState.priority) {
                Text("0 (default)").tag(Int?.none)
                ForEach(1...5, id: \.self) { value in
                    Text("\(value) of 5").tag(Int?.some(value))
                }
            }
        } header: {
            Text("Release")
        }
    }

    // MARK: - Release notes

    private func buildNotesSection() -> some View {
        Section {
            ForEach(Array(state.languages.enumerated()), id: \.element) { index, language in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(GooglePlayLanguage.displayName(for: language))
                            .fontWeight(.medium)
                        Spacer()
                        if index == 0 {
                            StackCapsuleBadge(title: String(localized: "Default"), color: .green)
                        } else if let source = state.notesCopiedFrom, state.notes[language]?.isEmpty == false {
                            Text("Copied from \(source)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else if state.notes[language]?.isEmpty ?? true {
                            Text("Missing")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                    TextEditor(text: Binding(
                        get: { viewModel.uiState.notes[language] ?? "" },
                        set: {
                            viewModel.uiState.notes[language] = $0
                            viewModel.notesChanged()
                        }
                    ))
                    .frame(minHeight: 72)
                    .accessibilityLabel(Text("Release notes in \(GooglePlayLanguage.displayName(for: language))"))
                    let count = state.notes[language]?.count ?? 0
                    Text("\(count) / \(GooglePlayReleaseDetailUiState.releaseNotesLimit)")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(count > GooglePlayReleaseDetailUiState.releaseNotesLimit ? .red : .secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .padding(.vertical, 2)
            }
        } header: {
            Text("Release Notes")
        }
    }

    // MARK: - Rollout

    private func buildRolloutSection() -> some View {
        Section {
            Toggle(String(localized: "Save as draft"), isOn: $viewModel.uiState.isDraft)
            if !state.isDraft && state.supportsStagedRollout {
                Picker(String(localized: "Staged Rollout"), selection: $viewModel.uiState.rolloutPercent) {
                    ForEach([1, 5, 10, 20, 50], id: \.self) { percent in
                        Text("\(GooglePlayPendingWrite.percent(Double(percent) / 100)) of users").tag(percent)
                    }
                    Text("All users").tag(100)
                }
            }
            LabeledContent(String(localized: "Country Targeting"), value: String(localized: "All countries"))
        } header: {
            Text("Rollout")
        } footer: {
            Text("A draft stays on the track without being served to anyone. Staged rollout is available for production and open testing.")
        }
    }
}

/// Bundles already uploaded to Google Play, newest first. Listing them opens
/// a temporary Play edit, so they load when this screen opens.
private struct GooglePlayBundlePicker: View {

    @ObservedObject var viewModel: GooglePlayNewReleaseViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section {
                if viewModel.uiState.isLoadingBundles {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                } else if let error = viewModel.uiState.bundlesError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.secondary)
                    StackTrackedButton(String(localized: "Retry"), button: .tryAgain, on: .googlePlayBundlePicker) {
                        Task { await viewModel.loadBundles() }
                    }
                } else if viewModel.uiState.bundles.isEmpty {
                    Text("No bundles uploaded")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(viewModel.uiState.bundles) { bundle in
                        StackChoiceRow(
                            title: String(localized: "Version code \(bundle.versionCode)"),
                            subtitle: bundle.sha256.map { "SHA-256 \($0.prefix(12))…" },
                            isSelected: viewModel.uiState.bundle == bundle
                        ) {
                            viewModel.selectBundle(bundle)
                            dismiss()
                        }
                    }
                }
            } footer: {
                Text("Google Play doesn't share a bundle's upload date or version name. Listing bundles briefly opens a Play edit.")
            }
        }
        .navigationTitle(String(localized: "App Bundles"))
        .navigationBarTitleDisplayMode(.inline)
        .trackScreen(.googlePlayBundlePicker)
        .task { await viewModel.loadBundles() }
    }
}
