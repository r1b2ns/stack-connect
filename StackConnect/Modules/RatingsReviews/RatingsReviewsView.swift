import SwiftUI

// MARK: - Factory

/// Ratings & Reviews of one app, for App Store Connect and Google Play alike:
/// the store comes from the account (`CustomerReviewsServiceFactory`). For
/// Google Play, `appId` and `bundleId` are both the package name.
@MainActor
struct RatingsReviewsViewFactory {
    static func build(appId: String, bundleId: String, appName: String, account: AccountModel) -> some View {
        RatingsReviewsEntryView(appId: appId, bundleId: bundleId, appName: appName, account: account)
    }
}

// MARK: - Entry

private struct RatingsReviewsEntryView: View {
    let appId: String
    let bundleId: String
    let appName: String
    let account: AccountModel

    @StateObject private var viewModel: RatingsReviewsViewModel

    init(appId: String, bundleId: String, appName: String, account: AccountModel) {
        self.appId = appId
        self.bundleId = bundleId
        self.appName = appName
        self.account = account
        _viewModel = StateObject(wrappedValue: RatingsReviewsViewModel(
            appId: appId,
            bundleId: bundleId,
            account: account,
            service: CustomerReviewsServiceFactory.makeService(for: account),
            cache: CustomerReviewsServiceFactory.makeCache(for: account, appId: appId)
        ))
    }

    var body: some View {
        RatingsReviewsView(viewModel: viewModel, appName: appName)
    }
}

// MARK: - View

struct RatingsReviewsView<ViewModel: RatingsReviewsViewModelProtocol>: View {

    @StateObject var viewModel: ViewModel
    let appName: String
    @EnvironmentObject private var homeCoordinator: HomeCoordinator

    var body: some View {
        buildContent()
            .navigationTitle(screenTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { buildToolbar() }
            .task { await viewModel.loadIfNeeded() }
            .refreshable { await viewModel.load() }
            // Swiping the composer away drops its draft and error too.
            .sheet(item: $viewModel.uiState.replyingTo, onDismiss: { viewModel.cancelReply() }) { review in
                ReplySheet(
                    review: review,
                    replyText: $viewModel.uiState.replyText,
                    footer: viewModel.uiState.traits.replyVisibilityNote,
                    characterLimit: viewModel.uiState.traits.replyCharacterLimit,
                    error: viewModel.uiState.replyError,
                    isSending: viewModel.uiState.isSending
                ) { text in
                    Task { await viewModel.reply(to: review, body: text) }
                } onCancel: {
                    viewModel.cancelReply()
                }
            }
            .toast(
                isPresented: $viewModel.uiState.showSyncToast,
                message: String(localized: "Syncing reviews...")
            )
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
            StackErrorContentView(message: error, reportContext: errorReportContext)
        } else if viewModel.uiState.hasMorePages {
            // Nothing so far, but the store has more pages (e.g. a rating filter
            // on Google Play, applied per page): offer the next one.
            ContentUnavailableView {
                Label(String(localized: "No Reviews"), systemImage: "star")
            } description: {
                VStack(spacing: 8) {
                    Text("No reviews in the pages loaded so far. More reviews are available.")
                    if let error = viewModel.uiState.loadMoreError {
                        Text(error)
                            .font(.footnote)
                    }
                }
            } actions: {
                if viewModel.uiState.isLoadingMore {
                    ProgressView()
                } else {
                    buildLoadMoreButton()
                }
                if viewModel.uiState.filterRating != nil {
                    Button(String(localized: "Show All Ratings")) {
                        Task { await viewModel.applyFilter(rating: nil) }
                    }
                }
            }
        } else {
            ContentUnavailableView {
                Label(String(localized: "No Reviews"), systemImage: "star")
            } description: {
                VStack(spacing: 8) {
                    Text("No customer reviews found for this app.")
                    if let note = viewModel.uiState.traits.listNote {
                        Text(note)
                            .font(.footnote)
                    }
                }
            } actions: {
                // A rating filter can hide every review: keep a way back.
                if viewModel.uiState.filterRating != nil {
                    Button(String(localized: "Show All Ratings")) {
                        Task { await viewModel.applyFilter(rating: nil) }
                    }
                }
            }
        }
    }

    private func buildList() -> some View {
        List {
            // A failed sync while cached reviews stay on screen.
            if let error = viewModel.uiState.error {
                StackInlineErrorSection(message: error, reportContext: errorReportContext)
            }
            buildSummarySection()
            buildFilterSection()

            Section {
                ForEach(viewModel.uiState.reviews) { review in
                    Button {
                        homeCoordinator.navigateToReviewDetail(
                            review: review,
                            appName: appName,
                            account: viewModel.uiState.account,
                            appId: viewModel.uiState.appId
                        )
                    } label: {
                        buildReviewRow(review)
                    }
                    .foregroundStyle(.primary)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        if !review.hasResponse && viewModel.uiState.canReply {
                            Button {
                                viewModel.uiState.replyingTo = review
                            } label: {
                                Label(String(localized: "Reply"), systemImage: "arrowshape.turn.up.left.fill")
                            }
                            .tint(.blue)
                        } else if let _ = review.responseId, viewModel.uiState.canDeleteReplies {
                            Button(role: .destructive) {
                                Task { await viewModel.deleteResponse(for: review) }
                            } label: {
                                Label(String(localized: "Delete Reply"), systemImage: "trash")
                            }
                        }
                    }
                }

                buildNextPageRow()
            } header: {
                Text("Reviews (\(viewModel.uiState.reviews.count))")
            } footer: {
                if let note = viewModel.uiState.traits.listNote {
                    Text(note)
                }
            }
        }
    }

    // MARK: - Next Page

    /// Where the next page goes: a spinner while it loads, otherwise "Load More"
    /// (or the last failure with "Try Again").
    ///
    /// The row loads the next page when it appears and again after every page
    /// that added reviews while it stayed on screen, so a list shorter than the
    /// screen keeps filling. A page that adds nothing (a rating filter on Google
    /// Play) or fails stops that and leaves the button: pages are never fetched
    /// in a loop on their own (Google Play counts each against an hourly quota).
    @ViewBuilder
    private func buildNextPageRow() -> some View {
        if viewModel.uiState.hasMorePages {
            VStack(spacing: 8) {
                if viewModel.uiState.isLoadingMore {
                    ProgressView()
                } else {
                    if let error = viewModel.uiState.loadMoreError {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    buildLoadMoreButton()
                }
            }
            .frame(maxWidth: .infinity)
            .listRowBackground(Color.clear)
            .task(id: viewModel.uiState.reviews.count) {
                await viewModel.loadMore()
            }
        }
    }

    private func buildLoadMoreButton() -> some View {
        Button(viewModel.uiState.loadMoreError == nil
            ? String(localized: "Load More Reviews")
            : String(localized: "Try Again")
        ) {
            Task { await viewModel.loadMore() }
        }
    }

    // MARK: - Summary Section

    @ViewBuilder
    private func buildSummarySection() -> some View {
        if let average = viewModel.uiState.storeAverageRating, average > 0 {
            Section {
                VStack(spacing: 6) {
                    Text(String(format: "%.1f", average))
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                    buildStarRow(rating: Int(average.rounded()))
                    Text(viewModel.uiState.ratingCountLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
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
        if viewModel.uiState.showsSortMenu {
            buildSortMenu()
        }
    }

    private func buildSortMenu() -> some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Menu {
                ForEach(viewModel.uiState.traits.sortOptions) { option in
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

    private var screenTitle: String {
        String(localized: "Ratings & Reviews")
    }

    /// Where an error on this screen happened, for its shared report.
    private var errorReportContext: ErrorReportContext {
        ErrorReportContext(
            screen: screenTitle,
            account: viewModel.uiState.account,
            appName: appName,
            appIdentifier: viewModel.uiState.bundleId
        )
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
}

// MARK: - Reply Sheet

/// Swipe-to-reply composer: the review being answered above the editor.
struct ReplySheet: View {

    let review: CustomerReviewModel
    @Binding var replyText: String
    /// Who will see the reply (store specific).
    let footer: String
    var characterLimit: Int? = nil
    var error: String? = nil
    let isSending: Bool
    let onSend: (String) -> Void
    let onCancel: () -> Void

    var body: some View {
        StackReplyComposer(
            title: String(localized: "Reply to Review"),
            confirmTitle: String(localized: "Send"),
            text: $replyText,
            footer: footer,
            characterLimit: characterLimit,
            error: error,
            editorMinHeight: 120,
            isSending: isSending,
            onSend: onSend,
            onCancel: onCancel
        ) {
            buildReviewSection()
        }
    }

    private func buildReviewSection() -> some View {
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
    }
}
