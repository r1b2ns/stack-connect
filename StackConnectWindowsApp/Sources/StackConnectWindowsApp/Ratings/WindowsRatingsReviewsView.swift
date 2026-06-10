import SwiftCrossUI
import StackHomeCore
import StackProtocols
import WindowsAppCore

// T-W19 — Ratings & Reviews screen for the Windows GUI.
//
// Composes the aggregate rating card (T-W17), paginated review rows (T-W18),
// and the Load More button (T-W04) into a full screen bound to
// `WindowsRatingsReviewsModel` (T-W16).
//
// Layout: toolbar (back + title) -> aggregate rating card -> scrollable
// reviews list -> Load More button. State handling: independent rating vs.
// reviews loading (AC-W10-2), first-page loading indicator (AC-W11-3),
// empty state (AC-W11-4), non-blocking error banner with retry (AC-W11-5),
// rating-unavailable fallback (AC-W10-3).
//
// Row tap pushes `.reviewDetail(reviewId:appId:accountId:)` via the
// coordinator (AC-W11-6). The destination screen (T-W23) is wired later.
//
// The view does NOT wire `.ratingsAndReviews` into RootView — that is T-W21.
// This screen is standalone: it exposes a Factory so RootView can instantiate
// it when the route is resolved.
//
// Follows the Factory + direct-init pattern used by `WindowsAppDetailView`
// (T-W12): no Entry/StateObject layer because SwiftCrossUI uses `@State`
// (not `@StateObject`) and the model is created externally by RootView's
// cache (or the factory).

// MARK: - Factory

/// Factory for the Ratings & Reviews screen. Creates the model and view,
/// matching the Factory pattern used by `WindowsAppDetailView` (T-W12).
/// The caller (RootView / T-W21) provides the navigation coordinator and
/// storage; the factory creates the model internally.
@MainActor
enum WindowsRatingsReviewsViewFactory {

    /// Builds the Ratings & Reviews screen with a fresh model.
    ///
    /// - Parameters:
    ///   - appId: The App Store app identifier.
    ///   - bundleId: The app's bundle identifier (for iTunes lookup).
    ///   - accountId: The owning account identifier.
    ///   - coordinator: The navigation coordinator.
    ///   - model: The ratings & reviews model (created by RootView cache).
    static func build(
        appId: String,
        bundleId: String,
        accountId: String,
        coordinator: WindowsHomeCoordinator,
        model: WindowsRatingsReviewsModel
    ) -> WindowsRatingsReviewsView {
        WindowsRatingsReviewsView(
            appId: appId,
            bundleId: bundleId,
            accountId: accountId,
            coordinator: coordinator,
            model: model
        )
    }
}

// MARK: - View

struct WindowsRatingsReviewsView: View {

    /// The app id this screen displays ratings/reviews for.
    let appId: String
    /// The app's bundle identifier (for iTunes aggregate rating lookup).
    let bundleId: String
    /// The owning account identifier.
    let accountId: String
    /// Navigation coordinator -- Back pops, row taps push reviewDetail.
    @State private var coordinator: WindowsHomeCoordinator
    /// The ratings & reviews model. Observed via `@State` so the view
    /// redraws when the model's `@Published` uiState changes.
    @State private var model: WindowsRatingsReviewsModel

    init(
        appId: String,
        bundleId: String,
        accountId: String,
        coordinator: WindowsHomeCoordinator,
        model: WindowsRatingsReviewsModel
    ) {
        self.appId = appId
        self.bundleId = bundleId
        self.accountId = accountId
        _coordinator = State(wrappedValue: coordinator)
        _model = State(wrappedValue: model)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                buildToolbar()
                buildRatingSection()
                buildReviewsErrorBanner()
                buildReviewsContent()
                Spacer()
            }
            .padding(16)
            .frame(maxWidth: 860)
        }
        .task {
            await model.loadRatingsIfNeeded(
                appId: appId,
                bundleId: bundleId,
                accountId: accountId
            )
        }
    }

    // MARK: - Toolbar (back + title + refresh)

    /// Header: "< Back" on the left, "Refresh" on the right. Title below.
    @ViewBuilder
    private func buildToolbar() -> some View {
        VStack(spacing: 12) {
            HStack {
                WindowsBackButtonView(onBack: { coordinator.pop() })
                Spacer()
                Button("Refresh") {
                    Task {
                        await model.loadRatingsIfNeeded(
                            appId: appId,
                            bundleId: bundleId,
                            accountId: accountId
                        )
                    }
                }
            }
            HStack {
                Text("Ratings & Reviews")
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
            }
        }
    }

    // MARK: - Aggregate Rating Section (AC-W10-1, AC-W10-2, AC-W10-3)

    /// The aggregate rating card section. Shows independently from the
    /// reviews list (AC-W10-2): its loading state uses `isLoadingRating`.
    @ViewBuilder
    private func buildRatingSection() -> some View {
        if model.uiState.isLoadingRating {
            // Rating is loading independently of reviews
            HStack(spacing: 8) {
                ProgressView()
                Text("Loading rating...")
                    .foregroundColor(.gray)
                Spacer()
            }
        } else if let rating = model.uiState.aggregateRating {
            // AC-W10-1: Show the aggregate card (delegates formatting to the card)
            WindowsAggregateRatingCard(rating: rating)
        } else if model.uiState.ratingError != nil {
            // AC-W10-3: iTunes lookup failed -> "Rating unavailable" indicator
            buildRatingUnavailableBanner()
        }
    }

    /// Non-blocking "Rating unavailable" banner (AC-W10-3). Reviews remain
    /// visible below.
    private func buildRatingUnavailableBanner() -> some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(Color.orange)
                .frame(width: 4)
                .cornerRadius(8)

            HStack(spacing: 8) {
                Text("Rating unavailable")
                    .foregroundColor(.orange)
                Spacer()
            }
            .padding(12)
        }
        .background(Color(white: 0.94))
        .cornerRadius(8)
    }

    // MARK: - Reviews Error Banner (AC-W11-5)

    /// Non-blocking error banner for reviews failures. Shows above the
    /// reviews list so cached reviews (if any) remain visible below.
    /// Includes a "Retry" button.
    @ViewBuilder
    private func buildReviewsErrorBanner() -> some View {
        if let error = model.uiState.reviewsError {
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
                            await model.loadRatingsIfNeeded(
                                appId: appId,
                                bundleId: bundleId,
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

    // MARK: - Reviews Content (AC-W11-1 through AC-W11-6)

    /// The reviews list area. Handles first-page loading, empty state, and
    /// the populated list with Load More.
    @ViewBuilder
    private func buildReviewsContent() -> some View {
        if model.uiState.isLoading && model.uiState.reviews.isEmpty {
            // AC-W11-3: First-page loading state; no partial/stale rows
            buildFirstPageLoading()
        } else if !model.uiState.isLoading && model.uiState.reviews.isEmpty && model.uiState.reviewsError == nil {
            // AC-W11-4: Zero reviews -> empty state; no Load More button
            buildEmptyState()
        } else if !model.uiState.reviews.isEmpty {
            // Populated: show reviews list + optional Load More
            buildReviewsList()
        }
        // When isLoading && reviews.isEmpty && reviewsError != nil:
        // The error banner is already showing above; no content area needed.
    }

    /// First-page loading indicator (AC-W11-3).
    private func buildFirstPageLoading() -> some View {
        HStack(spacing: 8) {
            ProgressView()
            Text("Loading reviews...")
                .foregroundColor(.gray)
            Spacer()
        }
    }

    /// Empty state when zero reviews are returned (AC-W11-4).
    private func buildEmptyState() -> some View {
        VStack(spacing: 12) {
            Spacer()
            Text("\u{2B50}")
                .font(.title2)
                .foregroundColor(.gray)
            Text("No Reviews Yet")
                .font(.title2)
                .fontWeight(.semibold)
            Text("This app has no customer reviews.")
                .foregroundColor(.gray)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Reviews List (AC-W11-1, AC-W11-2, AC-W11-6)

    /// The scrollable list of review rows with a Load More button at the
    /// bottom when more pages are available.
    @ViewBuilder
    private func buildReviewsList() -> some View {
        // Section header
        WindowsSectionHeader(title: "Reviews")

        // Review rows (AC-W11-1: delegates rendering to WindowsReviewRow)
        ForEach(model.uiState.reviews, id: \.id) { review in
            WindowsReviewRow(
                review: review,
                variant: .list,
                onTap: { tappedReview in
                    // AC-W11-6: Row tap -> push .reviewDetail carrying identifiers
                    coordinator.push(
                        .reviewDetail(
                            reviewId: tappedReview.id,
                            appId: appId,
                            accountId: accountId
                        )
                    )
                }
            )
        }

        // AC-W11-2: Load More button when more pages exist
        if model.uiState.canLoadMore {
            WindowsLoadMoreButton(
                isLoading: model.uiState.isLoadingMore,
                action: {
                    Task {
                        await model.loadNextPage(appId: appId)
                    }
                }
            )
        }
    }
}
