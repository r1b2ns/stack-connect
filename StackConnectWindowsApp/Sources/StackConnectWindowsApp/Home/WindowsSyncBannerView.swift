import SwiftCrossUI
import StackHomeCore

// Phase 4 · B1b-2 · T-B6 — the sync banner (US-003, design §2.4 item 2 / §2.2).
//
// SwiftCrossUI 0.7 has no native WinUI `InfoBar`, so this reproduces the
// InfoBar look manually: a short (~40px) horizontal strip with a 4px colored
// left border (a `Rectangle`), an indeterminate spinner (`ProgressView` — D5:
// the spinner primitive IS exposed in SwiftCrossUI 0.7, so we use it rather
// than a text fallback), and a status label.
//
// The banner is a pure function of the core `SyncState` that `WindowsHomeModel`
// republishes (via the `onStateChanged` callback bridge from `SyncService`).
// It does NOT subscribe to anything itself — the parent only mounts it while
// syncing — so when sync ends and the state flips, the slot drops the view and
// the banner disappears with no user action (AC-4). It is an inline strip in
// the content VStack, never an overlay, so it never captures input (AC-5).

struct WindowsSyncBannerView: View {

    /// The current sync snapshot from the shared core, delivered through
    /// `WindowsHomeModel.state.syncState`.
    let syncState: SyncState

    var body: some View {
        // Pure-helper drives the label. `nil` ⇒ idle ⇒ render nothing, so the
        // banner is invisible when not syncing (AC-1) even if mistakenly mounted.
        if let text = syncBannerText(for: syncState) {
            HStack(spacing: 0) {
                // 4px colored left border standing in for the InfoBar accent.
                // SwiftCrossUI 0.7 exposes neither `.clipped()` nor `.clipShape`,
                // and `.cornerRadius(8)` on the container does NOT clip children —
                // so the strip's right corners are rounded by the container while
                // its own corners stay square and bleed past the rounded card. We
                // round the strip itself to the same radius (the `cornerRadius`
                // modifier is documented to support exactly this case: rounding a
                // coloured rectangle on the WinUI backend), masking it to the card.
                Rectangle()
                    .fill(.blue)
                    .frame(width: 4)
                    .cornerRadius(8)

                HStack(spacing: 8) {
                    // D5: SwiftCrossUI 0.7 exposes an indeterminate ProgressView
                    // spinner, so we use it directly (no text/Rectangle fallback).
                    ProgressView()
                    Text(text)
                        .foregroundColor(.blue)
                    Spacer()
                }
                .padding(8)
            }
            .frame(height: 40)
            .background(Color(white: 0.94))
            .cornerRadius(8)
        }
    }
}

/// Derives the sync-banner label from a `SyncState`. Pure and side-effect free
/// so the label logic (TC-012 / TC-013) is unit-testable without a GUI.
///
/// - Returns: `nil` when not syncing (the banner is hidden); otherwise the
///   status string. With N > 0 accounts in progress it pluralizes
///   "Syncing N account(s)…"; with 0 accounts it falls back to "Syncing…".
func syncBannerText(for state: SyncState) -> String? {
    guard state.isSyncing else { return nil }

    let count = state.accountsInProgress.count
    guard count > 0 else { return "Syncing…" }

    let suffix = count == 1 ? "" : "s"
    return "Syncing \(count) account\(suffix)…"
}
