import SwiftCrossUI
import StackHomeCore

// Phase 4 · B1b-2 · T-C2 — the "Awaiting Release" Home widget view (US-007
// AC-3, design §2.5). Windows counterpart of the iOS `AwaitingReleaseWidgetView`
// in `HomeWidgetViewFactory.swift`: same data (`AwaitingReleaseWidget.data`,
// `AwaitingReleaseWidgetData`), different UI framework.
//
// Renders, inside its own radius-8 card:
//   • header: 📤 glyph + bold "Awaiting Release" + "(count)" + Spacer.
//   • while loading → "Loading…" row (AC-5).
//   • no apps       → "Nothing awaiting release" row.
//   • apps          → one tappable row per app (36×36 gray placeholder + name +
//                     status + version). Apps with an active/paused phased
//                     release also show a "Day N of 7" text line and, when
//                     paused, a "Paused" indicator (AC-3, design §2.5). Tapping
//                     pushes `.appDetail` (AC-6).
//
// The phased gating ("active or paused", currentDayNumber) mirrors the iOS
// factory exactly so both platforms surface the same rows; the underlying
// categorization already ran in the widget's `load()` via `AppStatusCategorizer`.
// Per design §2.5 the phased progress is plain "Day N of 7" text (ProgressView
// treated as uncertain → text), not a progress bar.

struct WindowsAwaitingReleaseWidgetView: View {

    /// The Awaiting Release widget's typed result data from the shared core.
    let data: AwaitingReleaseWidgetData
    /// Whether the widget's `load()` is in flight (AC-5).
    let isLoading: Bool
    /// Pushes the App Detail route on tap (AC-6 — v1 placeholder).
    let onSelectApp: (AppModel) -> Void

    /// The total days an App Store phased release spans (Apple's 7-day rollout).
    private let phasedTotalDays = 7

    var body: some View {
        VStack(spacing: 12) {
            WindowsWidgetHeaderView(
                glyph: HomeWidgetKind.awaitingRelease.windowsGlyph,
                title: "Awaiting Release",
                count: data.apps.count
            )

            if isLoading {
                WindowsWidgetLoadingRow()
            } else if data.apps.isEmpty {
                WindowsWidgetEmptyRow(text: "Nothing awaiting release")
            } else {
                ForEach(data.apps, id: \.self) { app in
                    VStack(spacing: 4) {
                        WindowsWidgetAppRow(app: app, showsPlatform: false)
                        phasedRow(for: app)
                    }
                    .onTapGesture { onSelectApp(app) }
                }
            }
        }
        .windowsWidgetCard()
    }

    /// The optional "Day N of 7" / paused line for an app, shown only when it has
    /// an active or paused phased release with a known day number (matches the
    /// iOS factory's gating). Renders nothing otherwise.
    @ViewBuilder
    private func phasedRow(for app: AppModel) -> some View {
        if let phased = data.phasedByAppId[app.id],
           phased.state == .active || phased.state == .paused,
           let day = phased.currentDayNumber {
            HStack(spacing: 6) {
                if phased.state == .paused {
                    Text("⏸ Paused")
                        .foregroundColor(.orange)
                }
                Text("Day \(day) of \(phasedTotalDays)")
                    .foregroundColor(.gray)
                Spacer()
            }
            // Align under the app's text, past the 36px icon + 12px row spacing.
            .padding(.leading, 48)
        }
    }
}
