import SwiftUI

// MARK: - Factory

@MainActor
struct TipJarViewFactory {
    static func build() -> some View {
        TipJarEntry()
    }
}

// MARK: - Entry

private struct TipJarEntry: View {
    @StateObject private var viewModel = TipJarViewModel()

    var body: some View {
        TipJarView(viewModel: viewModel)
    }
}

// MARK: - View

/// Optional tips through In-App Purchase. Pushed inside the Home
/// `NavigationStack` (`HomeRoute.tipJar`), so it has no coordinator of its own.
struct TipJarView<ViewModel: TipJarViewModelProtocol>: View {

    @ObservedObject var viewModel: ViewModel

    var body: some View {
        buildContent()
            .navigationTitle(String(localized: "Support the Project"))
            .navigationBarTitleDisplayMode(.inline)
            .trackScreen(.tipJar)
            .task { await viewModel.load() }
            .alert(
                String(localized: "Purchase Failed"),
                isPresented: Binding(
                    get: { viewModel.uiState.errorMessage != nil },
                    set: { if !$0 { viewModel.dismissError() } }
                )
            ) {
                StackTrackedButton(String(localized: "OK"), button: .ok, on: .tipJar, role: .cancel) {
                    viewModel.dismissError()
                }
            } message: {
                Text(viewModel.uiState.errorMessage ?? "")
            }
            .sheet(isPresented: Binding(
                get: { viewModel.uiState.isShowingThankYou },
                set: { if !$0 { viewModel.dismissThankYou() } }
            )) {
                buildThankYouSheet()
            }
    }

    // MARK: - Content

    @ViewBuilder
    private func buildContent() -> some View {
        switch viewModel.uiState.phase {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .unavailable:
            buildUnavailable()
        case .loaded:
            buildList()
        }
    }

    private func buildList() -> some View {
        List {
            buildHeaderSection()
            if viewModel.uiState.isPending {
                buildPendingSection()
            }
            buildTipsSection()
        }
    }

    private func buildHeaderSection() -> some View {
        Section {
            VStack(spacing: 12) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.pink)
                    .accessibilityHidden(true)

                Text(String(localized: "Enjoying StackConnect?"))
                    .font(.title3)
                    .fontWeight(.semibold)
                    .multilineTextAlignment(.center)

                Text(String(localized: "StackConnect is and will stay free and open source. Tips don't unlock anything — they just help keep the project going."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
    }

    private func buildPendingSection() -> some View {
        Section {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "Purchase Pending"))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text(String(localized: "Your tip is waiting for approval. It will go through once it's approved."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "hourglass")
                    .foregroundStyle(.orange)
            }
        }
    }

    private func buildTipsSection() -> some View {
        Section {
            ForEach(viewModel.uiState.tips) { tip in
                StackTipRow(
                    emoji: tip.emoji,
                    title: tip.displayName,
                    subtitle: tip.description,
                    price: tip.displayPrice,
                    isPurchasing: viewModel.uiState.purchasingProductID == tip.id,
                    isDisabled: viewModel.uiState.isPurchasing
                ) {
                    Task { await viewModel.purchase(tip) }
                }
            }
        }
    }

    private func buildUnavailable() -> some View {
        ContentUnavailableView {
            Label(String(localized: "Tips Unavailable"), systemImage: "heart.slash")
        } description: {
            Text(String(localized: "Tips can't be loaded right now. Check your connection and try again."))
        } actions: {
            Button(String(localized: "Retry")) {
                Task { await viewModel.retry() }
            }
        }
    }

    private func buildThankYouSheet() -> some View {
        FeedbackScreen(
            type: .gratitude,
            image: "heart.circle.fill",
            title: String(localized: "Thank you!"),
            message: String(localized: "Your support means a lot and helps keep StackConnect going."),
            onDismiss: { viewModel.dismissThankYou() }
        )
        .presentationDetents([.medium])
    }
}
