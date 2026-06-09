import Foundation
import SwiftCrossUI
import StackHomeCore
import StackProtocols

#if canImport(os)
import os
#endif

// T-W16 — Ratings & Reviews model for the Windows GUI.
//
// SwiftCrossUI `ObservableObject` adapter that provides:
// - Aggregate rating card data (via `ITunesLookupService`)
// - Paginated customer reviews list (via `AppleConnectionProtocol`)
// - Independent loading states for rating vs. reviews (AC-W10-2)
// - Load More pagination with opaque cursor (AC-W11-2)
// - Hidden sort/filter plumbing for future UI
//
// Mirrors `WindowsAppDetailModel` conventions:
// `@MainActor`, `SwiftCrossUI.ObservableObject`/`@SwiftCrossUI.Published`, DI
// via init (`storage: PersistentStorable`, optional `connection`, lookup service),
// offline-first where applicable.

// MARK: - UI State

/// The complete UI state for the Ratings & Reviews screen.
public struct WindowsRatingsReviewsUiState {

    // MARK: Aggregate Rating

    /// The aggregate rating data (nil before load or on lookup failure).
    public var aggregateRating: AggregateRating?

    /// True while the aggregate rating is loading.
    public var isLoadingRating: Bool = false

    /// Non-nil when the iTunes lookup failed; reviews remain usable.
    /// Intended for a non-blocking "Rating unavailable" indicator.
    public var ratingError: String?

    // MARK: Reviews

    /// The accumulated list of customer reviews (page 1 + Load More pages).
    public var reviews: [CustomerReviewModel] = []

    /// True while the first page of reviews is loading.
    public var isLoading: Bool = false

    /// True while a Load More (next page) request is in flight.
    public var isLoadingMore: Bool = false

    /// Whether there are more pages to load (drives Load More visibility).
    public var canLoadMore: Bool = false

    /// Opaque pagination cursor for the next page. Memory-only; not persisted
    /// (TC-080 / R4). A fresh model instance starts with nil and loads page 1.
    public var pageToken: String?

    /// Non-nil when the first page of reviews failed to load. The view can
    /// offer a retry action.
    public var reviewsError: String?

    public init(
        aggregateRating: AggregateRating? = nil,
        isLoadingRating: Bool = false,
        ratingError: String? = nil,
        reviews: [CustomerReviewModel] = [],
        isLoading: Bool = false,
        isLoadingMore: Bool = false,
        canLoadMore: Bool = false,
        pageToken: String? = nil,
        reviewsError: String? = nil
    ) {
        self.aggregateRating = aggregateRating
        self.isLoadingRating = isLoadingRating
        self.ratingError = ratingError
        self.reviews = reviews
        self.isLoading = isLoading
        self.isLoadingMore = isLoadingMore
        self.canLoadMore = canLoadMore
        self.pageToken = pageToken
        self.reviewsError = reviewsError
    }
}

// MARK: - Model

/// Ratings & Reviews model. Owns the state the view binds to and exposes
/// intents for loading aggregate ratings, fetching paginated reviews, and
/// eventually filtering/sorting.
@MainActor
public final class WindowsRatingsReviewsModel: SwiftCrossUI.ObservableObject {

    // MARK: - Published State

    @SwiftCrossUI.Published public private(set) var uiState = WindowsRatingsReviewsUiState()

    // MARK: - Dependencies

    private let storage: PersistentStorable
    private let connection: AppleConnectionProtocol?
    private let lookupService: ITunesLookupService

    // MARK: - Sort / Filter (hidden infrastructure for future UI)

    /// Current sort order passed to `fetchReviews`. Default: newest first.
    private var sort: ReviewSortOrder = .createdDateDescending

    /// Optional rating filter passed to `fetchReviews`. nil = all ratings.
    private var filterRating: [String]?

    // MARK: - Concurrency Guard

    /// Prevents duplicate Load More calls while one is already in flight.
    private var isLoadMoreInFlight = false

    // MARK: - Init

    /// Creates a new ratings & reviews model.
    ///
    /// - Parameters:
    ///   - storage: Persistent storage backend.
    ///   - connection: Optional Apple connection for fetching reviews. When nil,
    ///     only cached/stale data is shown (useful for offline or test scenarios).
    ///   - lookupService: The iTunes Lookup service for aggregate rating data.
    public init(
        storage: PersistentStorable,
        connection: AppleConnectionProtocol? = nil,
        lookupService: ITunesLookupService
    ) {
        self.storage = storage
        self.connection = connection
        self.lookupService = lookupService
    }

    // MARK: - Load Ratings & Reviews (Independent, Concurrent)

    /// Kicks off the aggregate rating fetch and the first page of reviews
    /// concurrently. The two loads are independent (AC-W10-2): a failure in
    /// one does not block the other.
    ///
    /// - Parameters:
    ///   - appId: The App Store app identifier (for reviews).
    ///   - bundleId: The app's bundle identifier (for iTunes lookup).
    ///   - accountId: The account identifier (for storage key context).
    public func loadRatingsIfNeeded(appId: String, bundleId: String, accountId: String) async {
        // Reset errors from a previous load
        uiState.ratingError = nil
        uiState.reviewsError = nil

        // Launch both loads concurrently and independently
        async let ratingTask: Void = loadAggregateRating(bundleId: bundleId)
        async let reviewsTask: Void = loadFirstPage(appId: appId)

        // Await both — each handles its own errors internally
        _ = await (ratingTask, reviewsTask)
    }

    // MARK: - Aggregate Rating (AC-W10-1, AC-W10-3)

    /// Fetches the aggregate rating via the iTunes Lookup service. On failure,
    /// leaves `aggregateRating` nil and sets a non-blocking error flag
    /// (AC-W10-3). Does NOT affect the reviews list.
    private func loadAggregateRating(bundleId: String) async {
        uiState.isLoadingRating = true

        let result = await lookupService.fetchAggregateRating(bundleId: bundleId)

        if let result {
            uiState.aggregateRating = result
        } else {
            // iTunes lookup failed entirely and no cached data is available
            uiState.aggregateRating = nil
            uiState.ratingError = "Rating unavailable"
            #if canImport(os)
            Logger(subsystem: "com.stackconnect.windows", category: "RatingsReviews")
                .warning("[RatingsReviews] Aggregate rating unavailable for \(bundleId, privacy: .public)")
            #endif
        }

        uiState.isLoadingRating = false
    }

    // MARK: - Reviews First Page (AC-W11-3, AC-W11-4, AC-W11-5)

    /// Fetches the first page of reviews. Sets `isLoading` during the call.
    /// On success, populates reviews, cursor, and canLoadMore. On failure,
    /// sets a non-blocking error with retry capability (AC-W11-5).
    private func loadFirstPage(appId: String) async {
        uiState.isLoading = true
        uiState.reviewsError = nil

        guard let connection else {
            // No connection: offline mode; no reviews to load.
            uiState.isLoading = false
            return
        }

        do {
            let page = try await connection.fetchReviews(
                appId: appId,
                sort: sort,
                filterRating: filterRating,
                limit: 50,
                cursor: nil
            )

            uiState.reviews = page.reviews
            uiState.pageToken = page.cursor
            uiState.canLoadMore = page.hasNextPage
        } catch {
            #if canImport(os)
            Logger(subsystem: "com.stackconnect.windows", category: "RatingsReviews")
                .warning("[RatingsReviews] First page fetch failed for app \(appId, privacy: .public): \(error.localizedDescription, privacy: .public)")
            #endif
            // AC-W11-5: Non-blocking error + retry. Keep any already-loaded reviews
            // (e.g. from a previous successful load before a refresh attempt).
            uiState.reviewsError = "Failed to load reviews."
        }

        uiState.isLoading = false
    }

    // MARK: - Load More (AC-W11-2, TC-026, TC-027)

    /// Fetches the next page of reviews using the current cursor. Appends the
    /// results to the existing list, updates the cursor, and hides Load More
    /// when there are no more pages.
    ///
    /// Guards against concurrent/duplicate calls and against calling when no
    /// cursor is available.
    ///
    /// - Parameter appId: The App Store app identifier.
    public func loadNextPage(appId: String) async {
        // Guard: no cursor means no more pages
        guard uiState.pageToken != nil else { return }
        // Guard: prevent concurrent Load More calls
        guard !isLoadMoreInFlight else { return }

        isLoadMoreInFlight = true
        uiState.isLoadingMore = true

        guard let connection else {
            uiState.isLoadingMore = false
            isLoadMoreInFlight = false
            return
        }

        do {
            let page = try await connection.fetchReviews(
                appId: appId,
                sort: sort,
                filterRating: filterRating,
                limit: 50,
                cursor: uiState.pageToken
            )

            // Append new reviews to existing list
            uiState.reviews.append(contentsOf: page.reviews)
            uiState.pageToken = page.cursor
            uiState.canLoadMore = page.hasNextPage
        } catch {
            #if canImport(os)
            Logger(subsystem: "com.stackconnect.windows", category: "RatingsReviews")
                .warning("[RatingsReviews] Load More failed for app \(appId, privacy: .public): \(error.localizedDescription, privacy: .public)")
            #endif
            // On Load More failure, keep existing reviews. The cursor is still
            // valid so the user can retry.
        }

        uiState.isLoadingMore = false
        isLoadMoreInFlight = false
    }

    // MARK: - Sort / Filter Setters (hidden infrastructure)

    /// Updates the sort order. Does NOT trigger a reload — the caller should
    /// call `loadRatingsIfNeeded` again with a fresh first page.
    public func setSort(_ newSort: ReviewSortOrder) {
        sort = newSort
    }

    /// Updates the rating filter. Does NOT trigger a reload — the caller
    /// should call `loadRatingsIfNeeded` again with a fresh first page.
    public func setFilterRating(_ ratings: [String]?) {
        filterRating = ratings
    }
}
