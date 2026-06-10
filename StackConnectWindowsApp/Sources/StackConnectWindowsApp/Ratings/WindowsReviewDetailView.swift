import SwiftCrossUI
import StackHomeCore
import StackProtocols
import WindowsAppCore

// T-W23 — Review Detail screen for the Windows GUI.
//
// Displays a single customer review with full detail: rating stars, date+time,
// title, full body, reviewer nickname + glyph, territory + glyph. Below the
// review, a reply section shows either:
//   - "Write a Reply" button + helper text (create mode, AC-W12-2)
//   - Existing reply body + date + "Edit Reply" / "Delete Reply" (AC-W12-3)
//
// Reply/Delete buttons push routes via the coordinator (TC-033/035/037):
//   - .replyComposer(reviewId:accountId:existingReplyBody:) for create/edit
//   - .deleteReplyConfirm(reviewId:responseId:accountId:) for delete
// The destination screens (T-W24/T-W25) and RootView wiring (T-W27) are
// separate tasks.
//
// A "Copy" button calls `model.copyReviewToClipboard()` and renders
// `clipboardMessage` as a transient banner (AC-W14-1/2, TC-040/041).
//
// Sync errors are rendered as non-blocking banners with cached content still
// visible (TC-042).
//
// Follows the Factory + direct-init pattern used by `WindowsRatingsReviewsView`
// (T-W19) and `WindowsAppDetailView` (T-W12): no Entry/StateObject layer
// because SwiftCrossUI uses `@State` (not `@StateObject`) and the model is
// created externally by RootView's cache (or the factory).

// MARK: - Factory

/// Factory for the Review Detail screen. Creates the model and view, matching
/// the Factory pattern used by `WindowsRatingsReviewsView` (T-W19).
/// The caller (RootView / T-W27) provides the navigation coordinator and
/// model; the factory wires them together.
@MainActor
enum WindowsReviewDetailViewFactory {

    /// Builds the Review Detail screen.
    ///
    /// - Parameters:
    ///   - reviewId: The customer review identifier.
    ///   - appId: The App Store app identifier.
    ///   - accountId: The owning account identifier.
    ///   - coordinator: The navigation coordinator.
    ///   - model: The review detail model (created by RootView cache).
    static func build(
        reviewId: String,
        appId: String,
        accountId: String,
        coordinator: WindowsHomeCoordinator,
        model: WindowsReviewDetailModel
    ) -> WindowsReviewDetailView {
        WindowsReviewDetailView(
            reviewId: reviewId,
            appId: appId,
            accountId: accountId,
            coordinator: coordinator,
            model: model
        )
    }
}

// MARK: - View

struct WindowsReviewDetailView: View {

    /// Success message returned by `copyReviewToClipboard()`. Used to pick
    /// banner colour without duplicating the literal (SF-2).
    private let clipboardSuccessMessage = "Copied!"

    /// The customer review identifier.
    let reviewId: String
    /// The App Store app identifier.
    let appId: String
    /// The owning account identifier.
    let accountId: String
    /// Navigation coordinator -- Back pops, reply/delete push sub-routes.
    @State private var coordinator: WindowsHomeCoordinator
    /// The review detail model. Observed via `@State` so the view redraws
    /// when the model's `@Published` uiState changes.
    @State private var model: WindowsReviewDetailModel

    init(
        reviewId: String,
        appId: String,
        accountId: String,
        coordinator: WindowsHomeCoordinator,
        model: WindowsReviewDetailModel
    ) {
        self.reviewId = reviewId
        self.appId = appId
        self.accountId = accountId
        _coordinator = State(wrappedValue: coordinator)
        _model = State(wrappedValue: model)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                buildToolbar()
                buildClipboardBanner()
                buildSyncErrorBanner()
                buildContent()
                Spacer()
            }
            .padding(16)
            .frame(maxWidth: 860)
        }
        .task {
            await model.loadReviewIfNeeded(
                reviewId: reviewId,
                appId: appId,
                accountId: accountId
            )
        }
    }

    // MARK: - Toolbar (back + title + Copy + Refresh)

    /// Header: "< Back" on the left, "Copy" and "Refresh" on the right.
    /// Title below.
    @ViewBuilder
    private func buildToolbar() -> some View {
        VStack(spacing: 12) {
            HStack {
                WindowsBackButtonView(onBack: { coordinator.pop() })
                Spacer()
                // Copy button (AC-W14-1/2, TC-040/041)
                Button("Copy") {
                    model.copyReviewToClipboard()
                }
                // Refresh button
                Button("Refresh") {
                    Task {
                        await model.loadReviewIfNeeded(
                            reviewId: reviewId,
                            appId: appId,
                            accountId: accountId
                        )
                    }
                }
            }
            HStack {
                Text("Review Detail")
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
            }
        }
    }

    // MARK: - Clipboard Banner (AC-W14-1/2, TC-040/041)

    /// Transient clipboard confirmation or error banner. Shows "Copied!" on
    /// success (TC-040) or "Clipboard not available on this host" on macOS
    /// fallback (TC-041). Auto-dismisses after 2 seconds via the model.
    @ViewBuilder
    private func buildClipboardBanner() -> some View {
        if let message = model.uiState.clipboardMessage {
            HStack(spacing: 0) {
                Rectangle()
                    .fill(message == clipboardSuccessMessage ? Color.green : Color.orange)
                    .frame(width: 4)
                    .cornerRadius(8)

                HStack(spacing: 8) {
                    Text(message)
                        .foregroundColor(message == clipboardSuccessMessage ? .green : .orange)
                    Spacer()
                }
                .padding(12)
            }
            .background(Color(white: 0.94))
            .cornerRadius(8)
        }
    }

    // MARK: - Sync Error Banner (TC-042)

    /// Non-blocking error banner for sync failures. Shows above the review
    /// content so cached review data (if any) remains visible below.
    @ViewBuilder
    private func buildSyncErrorBanner() -> some View {
        if let error = model.uiState.syncError {
            HStack(spacing: 0) {
                Rectangle()
                    .fill(Color.orange)
                    .frame(width: 4)
                    .cornerRadius(8)

                HStack(spacing: 8) {
                    Text(error)
                        .foregroundColor(.orange)
                    Spacer()
                    Button("Retry") {
                        Task {
                            await model.loadReviewIfNeeded(
                                reviewId: reviewId,
                                appId: appId,
                                accountId: accountId
                            )
                        }
                    }
                }
                .padding(12)
            }
            .background(Color(white: 0.94))
            .cornerRadius(8)
        }
    }

    // MARK: - Content (loading / populated)

    @ViewBuilder
    private func buildContent() -> some View {
        if model.uiState.isLoading && model.uiState.review == nil {
            // First load -> loading indicator, no partial/stale content
            buildLoadingState()
        } else if let review = model.uiState.review {
            buildPopulatedState(review: review)
        }
    }

    // MARK: - Loading State

    private func buildLoadingState() -> some View {
        HStack(spacing: 8) {
            ProgressView()
            Text("Loading review...")
                .foregroundColor(.gray)
            Spacer()
        }
    }

    // MARK: - Populated State (AC-W12-1/2/3)

    @ViewBuilder
    private func buildPopulatedState(review: CustomerReviewModel) -> some View {
        buildReviewCard(review: review)
        buildReplySection(review: review)
    }

    // MARK: - Review Card (AC-W12-1, TC-032)

    /// Full review display: stars, date+time, title, full body, nickname +
    /// glyph, territory + glyph.
    private func buildReviewCard(review: CustomerReviewModel) -> some View {
        VStack(spacing: 12) {
            // Row 1: Stars + Date+Time
            HStack(spacing: 6) {
                WindowsRatingStarsView(rating: review.rating)
                Spacer()
                if let date = review.createdDate {
                    Text(WindowsDateFormatting.absoluteDateTime(date))
                        .foregroundColor(.gray)
                }
            }

            // Row 2: Title (bold)
            if let title = review.title, !title.isEmpty {
                HStack {
                    Text(title)
                        .font(.title3)
                        .fontWeight(.bold)
                    Spacer()
                }
            }

            // Row 3: Full body (no truncation in detail view)
            if let body = review.body, !body.isEmpty {
                HStack {
                    Text(body)
                    Spacer()
                }
            }

            // Row 4: Nickname with person glyph (U+1F464)
            if let nickname = review.reviewerNickname, !nickname.isEmpty {
                HStack(spacing: 4) {
                    Text("\u{1F464}")
                    Text(nickname)
                        .foregroundColor(.gray)
                    Spacer()
                }
            }

            // Row 5: Territory with globe glyph (U+1F310)
            if let territory = review.territory, !territory.isEmpty {
                HStack(spacing: 4) {
                    Text("\u{1F310}")
                    Text(review.territoryDisplayName)
                        .foregroundColor(.gray)
                    Spacer()
                }
            }
        }
        .padding(16)
        .background(Color(white: 0.97))
        .cornerRadius(8)
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.gray.opacity(0.3), style: StrokeStyle(width: 1.0))
        }
    }

    // MARK: - Reply Section (AC-W12-2/3, TC-033/035/037)

    /// Reply section below the review card. In create mode shows a "Write a
    /// Reply" button with helper text. In edit mode shows the existing reply
    /// body, date, and Edit/Delete action buttons.
    @ViewBuilder
    private func buildReplySection(review: CustomerReviewModel) -> some View {
        WindowsSectionHeader(title: "Developer Response")

        // Reply error banner (non-blocking)
        if let replyError = model.uiState.replyError {
            HStack(spacing: 0) {
                Rectangle()
                    .fill(Color.red)
                    .frame(width: 4)
                    .cornerRadius(8)

                HStack(spacing: 8) {
                    Text(replyError)
                        .foregroundColor(.red)
                    Spacer()
                }
                .padding(12)
            }
            .background(Color(white: 0.94))
            .cornerRadius(8)
        }

        switch model.uiState.replyMode {
        case .create:
            buildCreateReplySection(review: review)
        case .edit(let responseId):
            buildEditReplySection(review: review, responseId: responseId)
        }
    }

    /// Create mode: "Write a Reply" button + helper text (AC-W12-2, TC-033).
    private func buildCreateReplySection(review: CustomerReviewModel) -> some View {
        VStack(spacing: 12) {
            HStack {
                Text("No developer response yet.")
                    .foregroundColor(.gray)
                Spacer()
            }

            HStack {
                Button(model.uiState.replyMode.buttonLabel) {
                    // TC-033: push replyComposer with nil existingReplyBody
                    coordinator.push(
                        .replyComposer(
                            reviewId: review.id,
                            accountId: accountId,
                            existingReplyBody: nil
                        )
                    )
                }
                Spacer()
            }
        }
        .padding(16)
        .background(Color(white: 0.97))
        .cornerRadius(8)
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.gray.opacity(0.3), style: StrokeStyle(width: 1.0))
        }
    }

    /// Edit mode: existing reply body + date + Edit/Delete buttons
    /// (AC-W12-3, TC-035/037).
    private func buildEditReplySection(review: CustomerReviewModel, responseId: String) -> some View {
        VStack(spacing: 12) {
            // Reply date
            if let replyDate = model.uiState.existingReplyDate {
                HStack {
                    Text(WindowsDateFormatting.absoluteDateTime(replyDate))
                        .foregroundColor(.gray)
                    Spacer()
                }
            }

            // Reply body
            if let replyBody = model.uiState.existingReplyBody, !replyBody.isEmpty {
                HStack {
                    Text(replyBody)
                    Spacer()
                }
            }

            // Action buttons: Edit Reply + Delete Reply
            HStack(spacing: 12) {
                // TC-035: push replyComposer with existing body
                Button(model.uiState.replyMode.buttonLabel) {
                    coordinator.push(
                        .replyComposer(
                            reviewId: review.id,
                            accountId: accountId,
                            existingReplyBody: model.uiState.existingReplyBody
                        )
                    )
                }

                // TC-037: push deleteReplyConfirm
                Button("Delete Reply") {
                    coordinator.push(
                        .deleteReplyConfirm(
                            reviewId: review.id,
                            responseId: responseId,
                            accountId: accountId
                        )
                    )
                }
                .foregroundColor(.red)

                Spacer()
            }

            // Pending indicator
            if model.uiState.isReplyPending {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Processing...")
                        .foregroundColor(.gray)
                    Spacer()
                }
            }
        }
        .padding(16)
        .background(Color(white: 0.97))
        .cornerRadius(8)
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.gray.opacity(0.3), style: StrokeStyle(width: 1.0))
        }
    }
}
