import SwiftUI

// MARK: - Factory

@MainActor
struct RatingsReviewsViewFactory {
    static func build(appId: String, bundleId: String, account: AccountModel) -> some View {
        RatingsReviewsEntryView(appId: appId, bundleId: bundleId, account: account)
    }
}

// MARK: - Entry

private struct RatingsReviewsEntryView: View {
    let appId: String
    let bundleId: String
    let account: AccountModel

    @StateObject private var viewModel: RatingsReviewsViewModel

    init(appId: String, bundleId: String, account: AccountModel) {
        self.appId = appId
        self.bundleId = bundleId
        self.account = account
        _viewModel = StateObject(wrappedValue: RatingsReviewsViewModel(appId: appId, bundleId: bundleId, account: account))
    }

    var body: some View {
        RatingsReviewsView(viewModel: viewModel)
    }
}

// MARK: - View

struct RatingsReviewsView<ViewModel: RatingsReviewsViewModelProtocol>: View {

    @ObservedObject var viewModel: ViewModel
    @EnvironmentObject private var homeCoordinator: HomeCoordinator

    var body: some View {
        buildContent()
            .navigationTitle(String(localized: "Ratings & Reviews"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { buildToolbar() }
            .task { await viewModel.load() }
            .refreshable { await viewModel.load() }
            .sheet(item: $viewModel.uiState.replyingTo) { review in
                ReplySheet(
                    review: review,
                    replyText: $viewModel.uiState.replyText,
                    isSending: viewModel.uiState.isSending
                ) { text in
                    Task { await viewModel.reply(to: review, body: text) }
                } onCancel: {
                    viewModel.uiState.replyingTo = nil
                    viewModel.uiState.replyText = ""
                }
            }
            .toast(message: $viewModel.uiState.toastMessage)
    }

    // MARK: - Content

    @ViewBuilder
    private func buildContent() -> some View {
        if viewModel.uiState.isLoading && viewModel.uiState.reviews.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.uiState.reviews.isEmpty {
            buildEmptyState()
        } else {
            buildList()
        }
    }

    @ViewBuilder
    private func buildEmptyState() -> some View {
        if let error = viewModel.uiState.error {
            ContentUnavailableView {
                Label(String(localized: "Error"), systemImage: "exclamationmark.triangle")
            } description: {
                Text(error)
            }
        } else {
            ContentUnavailableView {
                Label(String(localized: "No Reviews"), systemImage: "star")
            } description: {
                Text("No customer reviews found for this app.")
            }
        }
    }

    private func buildList() -> some View {
        List {
            buildSummarySection()
            buildFilterSection()

            Section {
                ForEach(viewModel.uiState.reviews) { review in
                    Button {
                        homeCoordinator.navigateToReviewDetail(review: review, account: viewModel.uiState.account)
                    } label: {
                        buildReviewRow(review)
                    }
                    .foregroundStyle(.primary)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        if !review.hasResponse && viewModel.uiState.account.canEdit(.review) {
                            Button {
                                viewModel.uiState.replyingTo = review
                            } label: {
                                Label(String(localized: "Reply"), systemImage: "arrowshape.turn.up.left.fill")
                            }
                            .tint(.blue)
                        } else if let _ = review.responseId, viewModel.uiState.account.canDelete(.review) {
                            Button(role: .destructive) {
                                Task { await viewModel.deleteResponse(for: review) }
                            } label: {
                                Label(String(localized: "Delete Reply"), systemImage: "trash")
                            }
                        }
                    }
                }

                // Infinite scroll trigger
                if viewModel.uiState.hasMorePages {
                    HStack {
                        Spacer()
                        if viewModel.uiState.isLoadingMore {
                            ProgressView()
                        } else {
                            Color.clear.frame(height: 1)
                        }
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                    .onAppear {
                        Task { await viewModel.loadMore() }
                    }
                }
            } header: {
                Text("Reviews (\(viewModel.uiState.reviews.count))")
            }
        }
    }

    // MARK: - Summary Section

    private func buildSummarySection() -> some View {
        Section {
            HStack(spacing: 16) {
                VStack(spacing: 4) {
                    Text(String(format: "%.1f", viewModel.uiState.averageRating))
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                    buildStarRow(rating: Int(viewModel.uiState.averageRating.rounded()))
                    Text(viewModel.uiState.ratingCountLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(minWidth: 80)

                VStack(spacing: 4) {
                    ForEach((1...5).reversed(), id: \.self) { star in
                        buildDistributionBar(
                            star: star,
                            count: viewModel.uiState.ratingDistribution[star] ?? 0,
                            total: viewModel.uiState.totalRatingCount
                        )
                    }
                }
            }
            .padding(.vertical, 8)
        }
    }

    private func buildDistributionBar(star: Int, count: Int, total: Int) -> some View {
        HStack(spacing: 6) {
            Text("\(star)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 12, alignment: .trailing)

            Image(systemName: "star.fill")
                .font(.system(size: 8))
                .foregroundStyle(.yellow)

            let fraction = total > 0 ? CGFloat(count) / CGFloat(total) : 0

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.gray.opacity(0.15))

                Capsule()
                    .fill(Color.yellow)
                    .frame(maxWidth: .infinity)
                    .scaleEffect(x: fraction, anchor: .leading)
            }
            .frame(height: 6)

            Text(count.formatted())
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 36, alignment: .leading)
        }
    }

    private func buildStarRow(rating: Int) -> some View {
        HStack(spacing: 2) {
            ForEach(1...5, id: \.self) { star in
                Image(systemName: star <= rating ? "star.fill" : "star")
                    .font(.caption2)
                    .foregroundStyle(.yellow)
            }
        }
    }

    // MARK: - Filter Section

    private func buildFilterSection() -> some View {
        Section {
            HStack {
                Text(String(localized: "Filter by Rating"))
                    .font(.subheadline)
                Spacer()
                Picker("", selection: Binding(
                    get: { viewModel.uiState.filterRating },
                    set: { newValue in
                        Task { await viewModel.applyFilter(rating: newValue) }
                    }
                )) {
                    Text(String(localized: "All")).tag(nil as Int?)
                    ForEach((1...5).reversed(), id: \.self) { star in
                        Label("\(star)", systemImage: "star.fill").tag(star as Int?)
                    }
                }
                .pickerStyle(.menu)
            }
        }
    }

    // MARK: - Review Row

    private func buildReviewRow(_ review: CustomerReviewModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                buildStarRow(rating: review.rating)

                Spacer()

                if let date = review.createdDate {
                    Text(formatDate(date))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let title = review.title, !title.isEmpty {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .lineLimit(2)
            }

            if let body = review.body, !body.isEmpty {
                Text(body)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }

            HStack {
                if let nickname = review.reviewerNickname {
                    Label(nickname, systemImage: "person.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if review.hasResponse {
                    Label(String(localized: "Replied"), systemImage: "checkmark.bubble.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private func buildToolbar() -> some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Menu {
                ForEach(ReviewSortOption.allCases) { option in
                    Button {
                        viewModel.uiState.sortOption = option
                        Task { await viewModel.load() }
                    } label: {
                        if viewModel.uiState.sortOption == option {
                            Label(option.displayName, systemImage: "checkmark")
                        } else {
                            Text(option.displayName)
                        }
                    }
                }
            } label: {
                Image(systemName: "arrow.up.arrow.down")
            }
        }
    }

    // MARK: - Helpers

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
}

// MARK: - Reply Sheet

struct ReplySheet: View {

    let review: CustomerReviewModel
    @Binding var replyText: String
    let isSending: Bool
    let onSend: (String) -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 2) {
                        ForEach(1...5, id: \.self) { star in
                            Image(systemName: star <= review.rating ? "star.fill" : "star")
                                .font(.caption)
                                .foregroundStyle(.yellow)
                        }
                    }

                    if let title = review.title {
                        Text(title)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }
                    if let body = review.body {
                        Text(body)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Review")
                }

                Section {
                    TextEditor(text: $replyText)
                        .frame(minHeight: 120)
                } header: {
                    Text("Your Reply")
                } footer: {
                    Text("Your reply will be visible to all users on the App Store.")
                }
            }
            .navigationTitle(String(localized: "Reply to Review"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) { onCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSending {
                        ProgressView()
                    } else {
                        Button(String(localized: "Send")) {
                            onSend(replyText)
                        }
                        .disabled(replyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            .disabled(isSending)
        }
    }
}
