import SwiftCrossUI

// Phase 4 · B1b-2 · T-D3 — reusable labeled placeholder screen (US-011, design D3).
//
// In v1 only Home and Customize Widgets are real screens; every other pushed
// route is a labeled placeholder ("<Name> — coming soon") with a working
// in-content "< Back" so push/pop is verifiable end-to-end (TC-068). One shared
// view backs every placeholder route so the layout/back behaviour stay
// consistent and there is no per-route copy-paste.
//
// `reimport` is a DISABLED placeholder (design D7): there is no live Apple sync
// on Windows v1, so it shows an explicit "not available on Windows" notice
// instead of "coming soon". Pass `isDisabled: true` for that case.
//
// Back is the shared `WindowsBackButtonView` (no duplicated pop logic): tapping
// it pops the coordinator route stack, returning to Home which re-renders
// against the same shared `model.state` so prior state (widgets, sync banner) is
// intact (AC-2, TC-067).

struct WindowsPlaceholderView: View {
    /// The screen name shown as the title (e.g. "Settings", "App Detail").
    let title: String
    /// `true` for routes intentionally unavailable in Windows v1 (`reimport`,
    /// design D7): swaps the "coming soon" subtitle for a disabled notice.
    let isDisabled: Bool
    /// Pops the route stack back to Home. The caller wires this to
    /// `coordinator.pop()` so this view owns no navigation state.
    let onBack: () -> Void

    init(title: String, isDisabled: Bool = false, onBack: @escaping () -> Void) {
        self.title = title
        self.isDisabled = isDisabled
        self.onBack = onBack
    }

    var body: some View {
        VStack(spacing: 16) {
            // Shared in-content "< Back" — single source of pop logic (T-B3).
            WindowsBackButtonView(onBack: onBack)

            Spacer()

            Text(title)
                .font(.title2)
                .fontWeight(.bold)

            // Disabled routes (reimport, D7) get an explicit unavailable notice;
            // every other v1 placeholder gets the "<Name> — coming soon" style.
            Text(subtitle)
                .foregroundColor(.gray)

            Spacer()
        }
        .padding(16)
        .frame(maxWidth: 860)
    }

    private var subtitle: String {
        isDisabled
            ? "Not available on Windows"
            : "\(title) — coming soon"
    }
}
