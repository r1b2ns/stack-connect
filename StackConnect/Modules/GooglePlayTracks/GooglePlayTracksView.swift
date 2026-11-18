import SwiftUI

// MARK: - Factory

@MainActor
struct GooglePlayTracksViewFactory {
    static func build(app: GooglePlayAppItem, account: AccountModel) -> some View {
        GooglePlayTracksEntry(app: app, account: account)
    }
}

// MARK: - Entry

private struct GooglePlayTracksEntry: View {

    @StateObject private var viewModel: GooglePlayTracksViewModel
    @StateObject private var writes: GooglePlayReleaseWriteViewModel

    init(app: GooglePlayAppItem, account: AccountModel) {
        _viewModel = StateObject(wrappedValue: GooglePlayTracksViewModel(app: app, account: account))
        _writes = StateObject(wrappedValue: GooglePlayReleaseWriteViewModel(app: app, account: account, screen: .googlePlayTracks))
    }

    var body: some View {
        GooglePlayTracksView(viewModel: viewModel, writes: writes)
    }
}

// MARK: - View

struct GooglePlayTracksView<ViewModel: GooglePlayTracksViewModelProtocol, Writes: GooglePlayReleaseWriteViewModelProtocol>: View {

    @ObservedObject var viewModel: ViewModel
    @ObservedObject var writes: Writes
    @EnvironmentObject private var homeCoordinator: HomeCoordinator

    var body: some View {
        StackLoadableContent(
            isLoading: viewModel.uiState.isLoading,
            hasContent: viewModel.uiState.hasContent,
            error: viewModel.uiState.error,
            errorReportContext: errorReportContext,
            errorCategory: viewModel.uiState.errorCategory,
            onRetry: { Task { await viewModel.load() } }
        ) {
            buildContent()
        }
        .navigationTitle(screenTitle)
        .navigationBarTitleDisplayMode(.inline)
        // Opening this screen is the explicit action that reads through a Play
        // edit — once: coming back from a pushed screen restarts `.task`, which
        // must not open another edit (D14).
        .task { await viewModel.loadIfNeeded() }
        .refreshable { await viewModel.load() }
        .onChange(of: writes.uiState.revision) {
            Task { await viewModel.reloadFromCache() }
        }
        .onChange(of: viewModel.uiState.tracks) {
            Task { await writes.loadContext() }
        }
        .googlePlayReleaseWrites(writes)
        .toast(
            isPresented: $viewModel.uiState.showSyncToast,
            message: String(localized: "Syncing tracks...")
        )
        .trackScreen(.googlePlayTracks)
    }

    private var screenTitle: String {
        String(localized: "Tracks & Releases")
    }

    /// Where an error on this screen happened, for its shared report.
    private var errorReportContext: ErrorReportContext {
        ErrorReportContext(screen: screenTitle, account: viewModel.uiState.account, app: viewModel.uiState.app)
    }

    // MARK: - Content

    @ViewBuilder
    private func buildContent() -> some View {
        let tracks = viewModel.uiState.tracks ?? []
        if tracks.isEmpty {
            ContentUnavailableView {
                Label(String(localized: "No Tracks"), systemImage: "square.stack.3d.up")
            } description: {
                Text("This app has no release track yet.")
            }
        } else {
            List {
                if let error = viewModel.uiState.error {
                    StackInlineErrorSection(message: error, reportContext: errorReportContext, errorCategory: viewModel.uiState.errorCategory)
                }

                ForEach(tracks) { track in
                    buildTrackSection(track)
                }
            }
        }
    }

    private func buildTrackSection(_ track: GooglePlayTrackModel) -> some View {
        Section {
            if track.releases.isEmpty {
                Text("No releases")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(track.releases.enumerated()), id: \.offset) { _, release in
                    StackTrackedButton(.release, on: .googlePlayTracks) {
                        homeCoordinator.navigateToGooglePlayReleaseDetail(release, track: track.track, app: viewModel.uiState.app, account: viewModel.uiState.account)
                    } label: {
                        GooglePlayReleaseRow(release: release)
                    }
                    .foregroundStyle(.primary)
                }
            }
        } header: {
            HStack {
                Label(track.kind.displayName, systemImage: track.kind.icon)
                Spacer()
                if writes.canPerform(.add) {
                    StackTrackedButton(.newRelease, on: .googlePlayTracks) {
                        writes.openNewRelease(track: track.track)
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.body)
                    }
                    .accessibilityLabel(Text("New release on \(track.kind.displayName)"))
                }
            }
        }
    }
}

// MARK: - Release Row

/// `{name} [status] … {chevron}` over the version codes and rollout.
private struct GooglePlayReleaseRow: View {

    let release: GooglePlayReleaseModel

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(release.displayName)
                        .font(.body)
                        .fontWeight(.medium)
                        .lineLimit(1)

                    StackCapsuleBadge(title: release.status.displayName, color: release.status.color)
                }

                if !release.versionCodes.isEmpty {
                    Text("Version codes: \(release.versionCodes.joined(separator: ", "))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if let fraction = release.rolloutFraction {
                    GooglePlayRolloutLabel(fraction: fraction, status: release.status)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Rollout

/// Staged-rollout percentage with a progress bar, e.g. "Staged rollout: 20%
/// of users". Shared by the tracks screen and the app detail release rows.
struct GooglePlayRolloutLabel: View {

    let fraction: Double
    let status: GooglePlayReleaseStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Staged rollout: \(fraction.formatted(.percent.precision(.fractionLength(0...2)))) of users")
                .font(.caption)
                .foregroundStyle(.secondary)

            ProgressView(value: min(max(fraction, 0), 1))
                .tint(status.color)
        }
    }
}
