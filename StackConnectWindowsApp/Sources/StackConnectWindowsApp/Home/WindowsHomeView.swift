import Foundation
import SwiftCrossUI
import StackHomeCore

// Phase 4 · B1b-2 · T-B4 / T-B5 / T-W29 — the Home content shell (design §2.4).
//
// A ScrollView + VStack (content capped ~860px) laying out, top to bottom:
//   1. toolbar row (T-B3, T-W29: + Refresh button for US-W17)
//   2. sync banner slot (shown while syncing)
//   3. provider cards grid (T-B5 — real radius-8 tinted cards in a manual
//      2-column grid + the Settings cell; see WindowsProviderCardView.swift)
//   4. widgets slot (WindowsWidgetContainerView — empty-state card or active
//      widget cards; T-C1. The real widget visuals land in T-C2.)
//
// Everything binds to the shared core state via `model.state`. The active-widget
// cards inside the container are still lightweight placeholders — the real
// widget visuals land in T-C2.

struct WindowsHomeView: View {
    let model: WindowsHomeModel
    let coordinator: WindowsHomeCoordinator

    var body: some View {
        // T-D4 (design §2.9): the content column is capped at 860px and the
        // vertical `ScrollView` horizontally centers content narrower than the
        // window, so the cap yields the centered layout (AC-1). The two
        // width-sensitive sections (toolbar labels + provider grid columns) each
        // resolve their `WindowsLayoutTier` from a scoped `GeometryReader`.
        //
        // Scoped (not one column-wide) readers on purpose: a single reader
        // wrapping the whole VStack would have to be pinned to a FIXED height,
        // which would clip the variable-height widget list (TC-085, N=20). Each
        // reader here wraps only a section with a computable intrinsic height
        // (the toolbar row, the grid), so the rest of the column — including the
        // widget list — keeps flowing and scrolling normally (AC-3). Both
        // readers sit inside the same 860-capped column, so they observe the
        // same width and resolve to the same tier.
        ScrollView {
            VStack(spacing: 16) {
                // Expiration alert (US-005, design §2.7) — rendered at the very
                // top, above the toolbar row, so it is visible regardless of
                // scroll. Driven entirely by the core's resolved expiration
                // state (Expired precedence lives in the core).
                expirationAlertSlot

                toolbarSlot

                syncBannerSlot
                loadingSlot
                providerGridSlot
                widgetsSlot

                Spacer()
            }
            .padding(16)
            .frame(maxWidth: 860)
        }
    }

    // MARK: - Toolbar slot (US-004 / US-009, responsive labels — T-D4)

    /// Fixed height reserved for the toolbar row so its scoped `GeometryReader`
    /// reports width without stretching vertically. The row is a single line of
    /// `.title2` text + buttons; 44px comfortably fits it at every tier.
    private let toolbarRowHeight = 44.0

    /// The toolbar row, width-aware via a scoped reader that resolves the
    /// responsive tier driving the action-label length (design §2.9).
    ///
    /// T-W29 (US-W17 AC-W17-2): the `onRefresh` closure triggers a full
    /// `loadDashboard()` reload. The async call is wrapped in a `Task` so the
    /// button handler stays synchronous (matching the pattern in
    /// `WindowsAppsListView`, `WindowsArchivedAppsView`, etc.). The core's
    /// `isLoading` flag is flipped true/false by `loadDashboard()`, and the
    /// existing `loadingSlot` (ProgressView + "Loading…") reacts to it
    /// automatically — no additional state management needed.
    private var toolbarSlot: some View {
        GeometryReader { proxy in
            WindowsToolbarView(
                title: "StackConnect",
                tier: windowsLayoutTier(availableWidth: proxy.size.width),
                onSync: { model.triggerSync() },
                onRefresh: { Task { await model.loadDashboard() } },
                onCustomizeWidgets: { coordinator.push(.customizeWidgets) }
            )
        }
        .frame(height: toolbarRowHeight)
    }

    // MARK: - Expiration alert slot (US-005)

    /// The inline expiration banner. The slot only owns placement (top of the
    /// content); the banner view reads the core's resolved expiration state and
    /// renders nothing when no alert is active.
    @ViewBuilder
    private var expirationAlertSlot: some View {
        WindowsAlertBannerView(model: model, coordinator: coordinator)
    }

    // MARK: - Sync banner slot (US-003)

    @ViewBuilder
    private var syncBannerSlot: some View {
        if model.state.syncState.isSyncing {
            WindowsSyncBannerView(syncState: model.state.syncState)
        }
    }

    // MARK: - Cold-start / loading slot (US-012)
    //
    // While the core's `loadDashboard()` runs, `model.state.isLoading` is true
    // (the core flips it true on entry and back to false via `defer`, T-A10), so
    // this slot shows a single inline indicator at the top of the content area
    // and drops it the instant the load completes (AC-1 / AC-2). It is purely a
    // function of `state.isLoading`, mounted/unmounted by the parent — it never
    // subscribes to anything itself.
    //
    // It deliberately sits BELOW the toolbar + sync-banner region rather than at
    // the very top of the VStack, so it never overlaps T-D1's expiration-alert
    // slot. It is an inline row, never an overlay, so it never blocks input and
    // the offline-first content (provider grid + widgets) keeps rendering its
    // SQLite snapshot underneath it (AC-3) — the indicator only ever sits above
    // already-visible content, signalling a refresh in flight.
    //
    // D5: SwiftCrossUI 0.7 DOES expose the indeterminate `ProgressView` spinner
    // (the same primitive `WindowsSyncBannerView` uses, T-B6), so this shell-
    // level affordance uses it directly + a "Loading…" label. (The per-widget
    // rows keep their text-only fallback — that is a separate, intentional D5
    // decision for the smaller in-card rows, not contradicted here.)

    @ViewBuilder
    private var loadingSlot: some View {
        if model.state.isLoading {
            HStack(spacing: 8) {
                ProgressView()
                Text("Loading…")
                    .foregroundColor(.gray)
                Spacer()
            }
        }
    }

    // MARK: - Provider cards grid (US-001 / US-002, responsive columns — T-D4)

    /// The provider cards + Settings cell laid out as a manual 2-column grid
    /// (no `LazyVGrid` in SwiftCrossUI 0.7). A scoped `GeometryReader` reads the
    /// proposed width, resolves the responsive `WindowsLayoutTier` (design §2.9),
    /// and the grid renders `tier.gridColumns` columns — collapsing 2 → 1 below
    /// the 680px breakpoint (AC-2). The cells (providers then the trailing
    /// Settings cell) come from the pure `homeGridCells` helper so the ordering
    /// is unit-testable without a GUI (US-001 AC-1, US-002 AC-1).
    @ViewBuilder
    private var providerGridSlot: some View {
        GeometryReader { proxy in
            let columns = windowsLayoutTier(availableWidth: proxy.size.width).gridColumns
            grid(columns: columns)
                // The reader fills the proposed size, so pin its height to the
                // grid's intrinsic height for THIS column count (rows of 120px
                // cards + 12px spacing) so it never steals scroll space or clips
                // cards. Single-column reserves more rows (taller); two-column
                // reserves fewer — pinning to the actual count avoids both a
                // clip and a large empty gap below the grid (AC-3).
                .frame(height: gridHeight(columns: columns))
        }
        // Outer height matches the tallest possible layout (single column) so
        // the GeometryReader itself never under-reserves before the inner pin is
        // applied; the inner frame then trims to the real column count.
        .frame(height: gridHeight(columns: 1))
    }

    /// Builds the grid from HStack rows of `columns` cells each. The cells are
    /// always rendered (US-001 AC-5: provider cards are never replaced by an
    /// empty state); the last row is padded with invisible spacers so a lone
    /// trailing cell keeps its column width.
    private func grid(columns: Int) -> some View {
        let cells = homeGridCells(providers: model.state.providers)
        let rows = cells.chunked(into: columns)
        return VStack(spacing: 12) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 12) {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                        card(for: cell)
                    }
                    // Pad short rows so a single trailing cell (e.g. Settings)
                    // does not stretch across the full row width.
                    ForEach(0..<(columns - row.count), id: \.self) { _ in
                        Color.clear.frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }

    /// Maps a pure grid cell to its card view, wiring the tap to the right route:
    /// providers push `.accountsList(provider)` (US-001 AC-2/AC-3); Settings
    /// pushes `.settings` (US-002 AC-2).
    private func card(for cell: HomeGridCell) -> some View {
        WindowsProviderCardView(
            glyph: cell.glyph,
            glyphColor: cell.tint,
            title: cell.title,
            tint: cell.tint
        ) {
            switch cell {
            case .provider(let provider): coordinator.push(.accountsList(provider))
            case .settings:               coordinator.push(.settings)
            }
        }
    }

    /// Intrinsic height of the grid for a given column count: the number of rows
    /// of 120px cards plus 12px inter-row spacing.
    private func gridHeight(columns: Int) -> Double {
        let cellCount = model.state.providers.count + 1 // + Settings cell
        let rowCount = max(1, Int(ceil(Double(cellCount) / Double(columns))))
        let cardHeight = 120.0
        let spacing = 12.0
        return Double(rowCount) * cardHeight + Double(rowCount - 1) * spacing
    }

    // MARK: - Widgets slot (US-006 / US-007, updated T-W03)
    //
    // The widgets section (empty state + active-widget cards) lives in its own
    // `WindowsWidgetContainerView` (T-C1). This slot only owns where it sits in
    // the Home layout — below the provider cards + Settings (US-006 AC-3) — and
    // wires the "Add Widgets" action to the coordinator route (US-006 AC-2).
    //
    // T-W03: the closures thread real ids from the `AppModel` /
    // `HomeRecentReview` into the parameterized routes (§2.2).
    // `onSeeMoreReviews` receives the first review's `AppModel` so it can route
    // to `.ratingsAndReviews` for that app (design §2.3, AC-W16-2). When the
    // widget is empty (nil app) the route falls back to `.comingSoon`.

    private var widgetsSlot: some View {
        WindowsWidgetContainerView(
            widgets: model.state.widgets,
            onAddWidgets: { coordinator.push(.customizeWidgets) },
            onSelectApp: { app in
                coordinator.push(
                    .appDetail(appId: app.id, accountId: app.accountId)
                )
            },
            onSelectReview: { item in
                coordinator.push(
                    .reviewDetail(
                        reviewId: item.review.id,
                        appId: item.app.id,
                        accountId: item.app.accountId
                    )
                )
            },
            onSeeMoreReviews: { app in
                if let app {
                    coordinator.push(
                        .ratingsAndReviews(
                            appId: app.id,
                            bundleId: app.bundleId,
                            accountId: app.accountId
                        )
                    )
                } else {
                    coordinator.push(.comingSoon(title: "All Reviews"))
                }
            }
        )
    }
}

// MARK: - Array chunking helper

private extension Array {
    /// Splits the array into chunks of at most `size` elements, preserving order.
    /// Used to turn the flat `[HomeGridCell]` into rows for the manual grid.
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
