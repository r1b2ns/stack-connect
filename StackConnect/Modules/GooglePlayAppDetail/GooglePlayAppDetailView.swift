import SwiftUI

// MARK: - Factory

@MainActor
struct GooglePlayAppDetailViewFactory {
    static func build(app: GooglePlayAppItem, account: AccountModel) -> some View {
        GooglePlayAppDetailEntry(app: app, account: account)
    }
}

// MARK: - Entry

private struct GooglePlayAppDetailEntry: View {

    @StateObject private var viewModel: GooglePlayAppDetailViewModel
    @StateObject private var writes: GooglePlayReleaseWriteViewModel

    init(app: GooglePlayAppItem, account: AccountModel) {
        _viewModel = StateObject(wrappedValue: GooglePlayAppDetailViewModel(app: app, account: account))
        _writes = StateObject(wrappedValue: GooglePlayReleaseWriteViewModel(app: app, account: account))
    }

    var body: some View {
        GooglePlayAppDetailView(viewModel: viewModel, writes: writes)
    }
}

// MARK: - View

struct GooglePlayAppDetailView<ViewModel: GooglePlayAppDetailViewModelProtocol, Writes: GooglePlayReleaseWriteViewModelProtocol>: View {

    @ObservedObject var viewModel: ViewModel
    @ObservedObject var writes: Writes
    @EnvironmentObject private var homeCoordinator: HomeCoordinator

    private var app: GooglePlayAppItem { viewModel.uiState.app }
    private var account: AccountModel { viewModel.uiState.account }

    var body: some View {
        buildContent()
            .navigationTitle(app.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .task { await viewModel.load() }
            .onChange(of: writes.uiState.revision) {
                Task { await viewModel.load() }
            }
            .googlePlayReleaseWrites(writes)
            .alert(
                String(localized: "Permission Denied"),
                isPresented: Binding(
                    get: { viewModel.uiState.permissionDeniedMessage != nil },
                    set: { if !$0 { viewModel.uiState.permissionDeniedMessage = nil } }
                )
            ) {
                Button(String(localized: "OK"), role: .cancel) {
                    viewModel.uiState.permissionDeniedMessage = nil
                }
            } message: {
                Text(viewModel.uiState.permissionDeniedMessage ?? "")
            }
    }

    // MARK: - Content

    @ViewBuilder
    private func buildContent() -> some View {
        if viewModel.uiState.isAppInScope {
            // Order of prototype screen 2: header, one section per track,
            // store presence, quality, Play Console-only note.
            List {
                buildHeaderSection()
                buildReleaseSections()
                buildStoreSection()
                buildReviewsSection()
                buildPlayConsoleSection()
            }
        } else {
            ContentUnavailableView {
                Label(String(localized: "App Unavailable"), systemImage: "lock.fill")
            } description: {
                Text("This app isn't included in the apps shared with this account.")
            }
        }
    }

    // MARK: - Header

    private func buildHeaderSection() -> some View {
        Section {
            HStack(spacing: 16) {
                StackAppIcon(url: app.iconURL, size: 64) {
                    StackIconTile(systemName: "play.fill", color: .green, size: 64, font: .title2)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(app.displayName)
                        .font(.title3)
                        .fontWeight(.semibold)

                    HStack(spacing: 4) {
                        Text(app.packageName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        CopyButton(text: app.packageName)
                    }

                    // "Android · Default language: English (US)" (prototype screen 2).
                    HStack(spacing: 4) {
                        StackPlatformGlyph.android.image
                            .foregroundStyle(Color.androidGlyph)
                            .accessibilityHidden(true)
                        Text(platformLine)
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var platformLine: String {
        guard let language = viewModel.uiState.defaultLanguage else { return String(localized: "Android") }
        return String(localized: "Android · Default language: \(GooglePlayLanguage.displayName(for: language))",
                      comment: "Google Play app detail header: platform, then the default store listing language.")
    }

    // MARK: - Menu

    private func buildReviewsSection() -> some View {
        Section {
            ForEach(viewModel.uiState.reviewSections) { section in
                buildMenuRow(section)
            }
        } header: {
            Text("Quality")
        }
    }

    private func buildStoreSection() -> some View {
        Section {
            ForEach(viewModel.uiState.storeSections) { section in
                buildMenuRow(section)
            }
        } header: {
            Text("Store presence")
        } footer: {
            Text("Opening these sections briefly opens a Play edit to read the data. Google allows one open edit per service account and app, so this cancels any edit this service account has open for the app — for example, a CI upload in progress. If your CI publishes with this service account, add a separate read-only one here instead.")
        }
    }

    // MARK: - Releases

    /// One section per track with a release (from the caches), "See all
    /// tracks" closing the last one. Without any cached release, a single
    /// Tracks & Releases row. Hidden without the `version` rule.
    @ViewBuilder
    private func buildReleaseSections() -> some View {
        if viewModel.uiState.canViewReleases {
            let sections = viewModel.uiState.releaseSections
            if sections.isEmpty {
                Section {
                    buildMenuRow(.tracks)
                } header: {
                    Text("Releases")
                }
            } else {
                ForEach(sections) { section in
                    Section {
                        ForEach(section.rows) { row in
                            Button {
                                open(row, in: section)
                            } label: {
                                GooglePlayAppDetailReleaseRowView(row: row)
                            }
                            .foregroundStyle(.primary)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                buildSwipeActions(row, in: section)
                            }
                        }
                        if section.id == sections.last?.id {
                            buildSeeAllTracksRow()
                        }
                    } header: {
                        Text(section.kind.displayName)
                    } footer: {
                        if section.id == sections.last?.id {
                            if writes.canPerform(.edit) {
                                Text("Swipe a release to halt, resume or complete its rollout. Opening all tracks or a release briefly opens a Play edit, like the store presence sections below.")
                            } else {
                                Text("Opening all tracks or a release briefly opens a Play edit, like the store presence sections below.")
                            }
                        }
                    }
                }
            }
        }
    }

    /// Mirrors the release detail's bottom bar (plan R8): the final action
    /// first (rightmost), each one confirmed before anything is sent.
    @ViewBuilder
    private func buildSwipeActions(_ row: GooglePlayAppDetailReleaseRow, in section: GooglePlayAppDetailTrackSection) -> some View {
        if let release = row.release {
            ForEach(viewModel.releaseActions(for: row, in: section).reversed(), id: \.self) { action in
                Button {
                    writes.start(action, release: release, track: section.track)
                } label: {
                    Label(action.shortTitle, systemImage: action.icon)
                }
                .tint(action.color)
            }
        }
    }

    private func buildSeeAllTracksRow() -> some View {
        Button {
            open(.tracks)
        } label: {
            HStack {
                Text("See all tracks")
                    .foregroundStyle(.secondary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .foregroundStyle(.primary)
    }

    /// Settings Google Play's API can't change (prototype screen 2).
    private func buildPlayConsoleSection() -> some View {
        Section {
            Text("Content rating, category, data safety, privacy policy, pricing and countries can't be changed through the Google Play API.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let url = URL(string: "https://play.google.com/console") {
                Link(String(localized: "Open Play Console"), destination: url)
            }
        } header: {
            Text("Only in Play Console")
        }
    }

    private func buildMenuRow(_ section: GooglePlayAppDetailSection) -> some View {
        Button {
            open(section)
        } label: {
            StackListRow(icon: section.icon, iconColor: section.color, title: section.title)
        }
        .foregroundStyle(.primary)
    }

    // MARK: - Navigation

    /// A release the tracks cache holds opens its detail; otherwise the tracks
    /// screen, which reads the release through a Play edit (an explicit tap).
    private func open(_ row: GooglePlayAppDetailReleaseRow, in section: GooglePlayAppDetailTrackSection) {
        if let denial = viewModel.denial(for: .tracks) {
            viewModel.presentDenial(denial)
            return
        }
        if let release = row.release {
            homeCoordinator.navigateToGooglePlayReleaseDetail(release, track: section.track, app: app, account: account)
        } else {
            homeCoordinator.navigateToGooglePlayTracks(app, account: account)
        }
    }

    private func open(_ section: GooglePlayAppDetailSection) {
        if let denial = viewModel.denial(for: section) {
            viewModel.presentDenial(denial)
            return
        }
        switch section {
        case .ratingsReviews:
            // Play reviews reuse the App Store screens through the reviews
            // provider seam; the package name is both the app id and bundle id.
            homeCoordinator.navigateToRatingsReviews(
                appId: app.packageName,
                bundleId: app.packageName,
                appName: app.displayName,
                account: account
            )
        case .storeListings:
            homeCoordinator.navigateToGooglePlayStoreListings(app, account: account)
        case .tracks:
            homeCoordinator.navigateToGooglePlayTracks(app, account: account)
        case .appDetails:
            homeCoordinator.navigateToGooglePlayAppInfo(app, account: account)
        }
    }
}

// MARK: - Section color

private extension GooglePlayAppDetailSection {
    var color: Color {
        switch self {
        case .ratingsReviews: return .yellow
        case .storeListings:  return .blue
        case .tracks:         return .green
        case .appDetails:     return .gray
        }
    }
}

// MARK: - Release row

/// `{name} [status]` over `● {lifecycle} · Version code {code}` and, while a
/// staged rollout runs, its percentage. The badge and rollout come from the
/// tracks cache only (they need an edit); the lifecycle line from the
/// edit-free release summaries.
private struct GooglePlayAppDetailReleaseRowView: View {

    let row: GooglePlayAppDetailReleaseRow

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(row.title)
                        .font(.body)
                        .fontWeight(.medium)
                        .lineLimit(1)

                    if let status = row.status {
                        StackCapsuleBadge(title: status.displayName, color: status.color)
                    }
                }

                if let state = row.lifecycleState {
                    StackStatusLine(color: state.color, text: lifecycleText(state))
                } else if let codes = versionCodesText {
                    Text(codes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if let fraction = row.rolloutFraction, let status = row.status {
                    GooglePlayRolloutLabel(fraction: fraction, status: status)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }

    private var versionCodesText: String? {
        switch row.versionCodes.count {
        case 0:  return nil
        case 1:  return String(localized: "Version code \(row.versionCodes[0])")
        default: return String(localized: "Version codes \(row.versionCodes.joined(separator: ", "))")
        }
    }

    /// "Published · Version code 4200".
    private func lifecycleText(_ state: GooglePlayReleaseLifecycleState) -> String {
        guard let codes = versionCodesText else { return state.displayName }
        return String(localized: "\(state.displayName) · \(codes)",
                      comment: "Google Play release row: lifecycle state, then the version codes.")
    }
}
