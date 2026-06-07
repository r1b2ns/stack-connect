import Foundation
import SwiftCrossUI
import StackHomeCore

// Phase 4 · B1b-2 · T-B4 / T-B5 — the Home content shell (design §2.4).
//
// A ScrollView + VStack (content capped ~860px) laying out, top to bottom:
//   1. toolbar row (T-B3)
//   2. sync banner slot (shown while syncing)
//   3. provider cards grid (T-B5 — real radius-8 tinted cards in a manual
//      2-column grid + the Settings cell; see WindowsProviderCardView.swift)
//   4. widgets slot (empty-state or a list of active widgets; widget views = T-C)
//
// Everything binds to the shared core state via `model.state`. The widget cells
// are still lightweight placeholders — the real widget visuals land in T-C*.

struct WindowsHomeView: View {
    let model: WindowsHomeModel
    let coordinator: WindowsHomeCoordinator

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                WindowsToolbarView(
                    title: "StackConnect",
                    onSync: { model.triggerSync() },
                    onCustomizeWidgets: { coordinator.push(.customizeWidgets) }
                )

                syncBannerSlot
                providerGridSlot
                widgetsSlot

                Spacer()
            }
            .padding(16)
            .frame(maxWidth: 860)
        }
    }

    // MARK: - Sync banner slot (US-003)

    @ViewBuilder
    private var syncBannerSlot: some View {
        if model.state.syncState.isSyncing {
            let count = model.state.syncState.accountsInProgress.count
            HStack(spacing: 8) {
                Text("Syncing \(count) account\(count == 1 ? "" : "s")…")
                    .foregroundColor(.blue)
                Spacer()
            }
            .padding(12)
            .background(Color(white: 0.94))
            .cornerRadius(8)
        }
    }

    // MARK: - Provider cards grid (US-001 / US-002)

    /// Width below which the 2-column grid collapses to a single column
    /// (design §2.9: < 680px → single column).
    private let singleColumnBreakpoint = 680.0

    /// The provider cards + Settings cell laid out as a manual 2-column grid
    /// (no `LazyVGrid` in SwiftCrossUI 0.7). The grid reads the proposed width
    /// and collapses to one column on narrow widths. The cells (providers then
    /// the trailing Settings cell) come from the pure `homeGridCells` helper so
    /// the ordering is unit-testable without a GUI (US-001 AC-1, US-002 AC-1).
    @ViewBuilder
    private var providerGridSlot: some View {
        GeometryReader { proxy in
            grid(columns: proxy.size.width < singleColumnBreakpoint ? 1 : 2)
        }
        // GeometryReader fills the proposed size, so cap its height to the grid's
        // intrinsic height (rows of 120px cards + 12px spacing) to avoid it
        // stealing vertical space from the scroll content. Reserve the tallest
        // layout — the single-column case (most rows) — so cards never clip when
        // the grid collapses on narrow widths; the grid is top-aligned, so the
        // 2-column layout simply leaves slack below.
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

    // MARK: - Widgets slot (US-006 / US-007)

    @ViewBuilder
    private var widgetsSlot: some View {
        if model.state.widgets.isEmpty {
            widgetsEmptyState
        } else {
            VStack(spacing: 8) {
                ForEach(model.state.widgets, id: \.id) { widget in
                    widgetCard(widget)
                }
            }
        }
    }

    private var widgetsEmptyState: some View {
        VStack(spacing: 8) {
            Text("[#]")
            Text("No widgets yet")
                .fontWeight(.semibold)
            Text("Add widgets to see your apps in review, awaiting release, and recent reviews.")
                .foregroundColor(.gray)
            Button("Add Widgets") {
                coordinator.push(.customizeWidgets)
            }
        }
        .padding(16)
        .background(Color(white: 0.95))
        .cornerRadius(8)
    }

    private func widgetCard(_ widget: any HomeWidget) -> some View {
        HStack(spacing: 12) {
            Text(glyph(for: widget.kind))
            Text(widget.kind.displayName)
                .fontWeight(.semibold)
            Spacer()
        }
        .padding(16)
        .background(Color(white: 0.95))
        .cornerRadius(8)
    }

    // MARK: - Icon substitution (design §2.8)
    //
    // The provider/Settings icon + color substitution now lives on `HomeGridCell`
    // (WindowsProviderCardView.swift). The widget-kind glyph stays here until the
    // widget views land (T-C*).

    private func glyph(for kind: HomeWidgetKind) -> String {
        switch kind {
        case .inReview: return "🔍"
        case .awaitingRelease: return "📤"
        case .recentReviews: return "💬"
        }
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
