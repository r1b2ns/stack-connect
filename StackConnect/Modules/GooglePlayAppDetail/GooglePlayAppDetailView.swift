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

    init(app: GooglePlayAppItem, account: AccountModel) {
        _viewModel = StateObject(wrappedValue: GooglePlayAppDetailViewModel(app: app, account: account))
    }

    var body: some View {
        GooglePlayAppDetailView(viewModel: viewModel)
    }
}

// MARK: - View

struct GooglePlayAppDetailView<ViewModel: GooglePlayAppDetailViewModelProtocol>: View {

    @ObservedObject var viewModel: ViewModel
    @EnvironmentObject private var homeCoordinator: HomeCoordinator

    private var app: GooglePlayAppItem { viewModel.uiState.app }
    private var account: AccountModel { viewModel.uiState.account }

    var body: some View {
        buildContent()
            .navigationTitle(app.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .task { await viewModel.load() }
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
            List {
                buildHeaderSection()
                buildReviewsSection()
                buildStoreSection()
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
                StackIconTile(systemName: "play.fill", color: .green, size: 64, font: .title2)

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

                    Label(String(localized: "Android"), systemImage: "smartphone")
                        .font(.caption)
                        .foregroundStyle(.green)

                    if let language = viewModel.uiState.defaultLanguage {
                        Text("Default language: \(GooglePlayLanguage.displayName(for: language))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Menu

    private func buildReviewsSection() -> some View {
        Section {
            ForEach(viewModel.uiState.reviewSections) { section in
                buildMenuRow(section)
            }
        } header: {
            Text("Reviews")
        }
    }

    private func buildStoreSection() -> some View {
        Section {
            ForEach(viewModel.uiState.storeSections) { section in
                buildMenuRow(section)
            }
        } header: {
            Text("Store")
        } footer: {
            Text("Opening these sections briefly opens a Play edit to read the data. Google allows one open edit per service account and app, so this cancels any edit this service account has open for the app — for example, a CI upload in progress. If your CI publishes with this service account, add a separate read-only one here instead.")
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
