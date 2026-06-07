import SwiftCrossUI
import StackHomeCore

// Phase 4 · B1b-2 · T-C2 — the "In Review" Home widget view (US-007 AC-2,
// design §2.5). The Windows counterpart of the iOS `InReviewWidgetView` in
// `HomeWidgetViewFactory.swift`: same data (`InReviewWidget.data`,
// `InReviewWidgetData`), different UI framework.
//
// Renders, inside its own radius-8 card (chrome owned here so each widget view
// is self-contained, mirroring `WindowsWidgetsEmptyStateView`):
//   • a header row: 🔍 glyph + bold "In Review" + "(count)" secondary + Spacer
//     (design §2.5, icon table §2.8).
//   • while `widget.isLoading`            → a single "Loading…" text row (AC-5,
//                                            design §2.5; ProgressView treated as
//                                            uncertain → text fallback).
//   • no apps                             → a single "No apps in review" row.
//   • apps                                → one tappable row per app (36×36 gray
//                                            placeholder icon + name + status +
//                                            version + platform), tapping pushes
//                                            `.appDetail` (AC-6, D4 — no image
//                                            fetch).
//
// All status/version/platform values come straight off the core `AppModel`; no
// status/categorization logic is reimplemented here (it already ran in the
// widget's `load()` via `AppStatusCategorizer`).

struct WindowsInReviewWidgetView: View {

    /// The In Review widget's typed result data from the shared core.
    let data: InReviewWidgetData
    /// Whether the widget's `load()` is in flight (AC-5).
    let isLoading: Bool
    /// Pushes the App Detail route on tap (AC-6 — v1 placeholder).
    let onSelectApp: (AppModel) -> Void

    var body: some View {
        VStack(spacing: 12) {
            WindowsWidgetHeaderView(
                glyph: "🔍",
                title: "In Review",
                count: data.apps.count
            )

            if isLoading {
                WindowsWidgetLoadingRow()
            } else if data.apps.isEmpty {
                WindowsWidgetEmptyRow(text: "No apps in review")
            } else {
                ForEach(data.apps, id: \.self) { app in
                    WindowsWidgetAppRow(app: app, showsPlatform: true)
                        .onTapGesture { onSelectApp(app) }
                }
            }
        }
        .windowsWidgetCard()
    }
}
