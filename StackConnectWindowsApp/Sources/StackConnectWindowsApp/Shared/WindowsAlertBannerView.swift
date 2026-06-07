import Foundation
import SwiftCrossUI
import StackHomeCore

// Phase 4 · Block D · T-D1 — the account-expiration alert (US-005, design §2.7 / §2.10).
//
// SwiftCrossUI 0.7 has no native WinUI `InfoBar` and no modal `.alert`, so the
// iOS modal alerts become an inline InfoBar banner rendered at the very top of
// the content area (above the toolbar row) so it is visible regardless of
// scroll (design §2.10 delta 2). It reproduces the InfoBar look manually: a 4px
// colored left-border strip (a `Rectangle`) — RED for Expired, AMBER for
// Expiring Soon — plus a title, a message, and the action buttons.
//
// All of the "which alert / precedence / session-warned" logic lives in the
// shared core `HomeViewModel` (T-A10): the core sets exactly one of
// `showExpiredAlert` / `showExpiringSoonAlert`, with Expired winning when an
// account is both expired and expiring (US-005 AC-7). This view only RENDERS
// the resolved state and calls the model's intents (re-import navigation,
// dismiss-expired, dismiss-expiring). It duplicates no expiration/date logic.

struct WindowsAlertBannerView: View {

    /// The shared-core adapter. The banner reads `model.state` (the resolved
    /// expiration flags) and calls the dismiss intents; it never re-derives
    /// precedence itself.
    let model: WindowsHomeModel
    /// Navigation coordinator — Re-import pushes the `.reimport` route
    /// (disabled placeholder in v1, D7).
    let coordinator: WindowsHomeCoordinator

    var body: some View {
        // Expired takes precedence (US-005 AC-7). The core already guarantees it
        // never sets both flags, but selecting Expired first here makes the
        // precedence explicit and robust at the render seam too.
        if model.state.showExpiredAlert, let account = model.state.expiredAccount {
            banner(
                accent: .red,
                title: "Account Expired",
                message: ExpirationAlertMessage.expired(accountName: account.name),
                primaryTitle: "Re-import File",
                secondaryTitle: "Cancel",
                onPrimary: { reimport() },
                onSecondary: { model.dismissExpiredAlert() }
            )
        } else if model.state.showExpiringSoonAlert, let account = model.state.expiringSoonAccount {
            banner(
                accent: .orange,
                title: "Account Expiring Soon",
                message: ExpirationAlertMessage.expiringSoon(
                    accountName: account.name,
                    expirationDate: account.expirationDate
                ),
                primaryTitle: "Re-import File",
                secondaryTitle: "OK",
                onPrimary: { reimport() },
                onSecondary: { model.dismissExpiringSoonAlert() }
            )
        }
    }

    /// Re-import: close the banner, then navigate to the v1 placeholder
    /// re-import route (US-005 AC-2 / AC-5; `.reimport` is a disabled
    /// placeholder per D7). We dismiss the matching alert first so the banner
    /// does not linger behind the pushed screen.
    private func reimport() {
        if model.state.showExpiredAlert {
            model.dismissExpiredAlert()
        } else {
            model.dismissExpiringSoonAlert()
        }
        coordinator.push(.reimport)
    }

    /// The shared InfoBar layout: a 4px accent left border + title/message stack
    /// + action buttons. The accent color is the only thing that differs between
    /// the Expired (red) and Expiring (amber) variants.
    private func banner(
        accent: Color,
        title: String,
        message: String,
        primaryTitle: String,
        secondaryTitle: String,
        onPrimary: @escaping () -> Void,
        onSecondary: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 0) {
            // 4px colored left border standing in for the InfoBar accent. As in
            // WindowsSyncBannerView, round the strip itself so its corners do not
            // bleed past the rounded card on the WinUI backend.
            Rectangle()
                .fill(accent)
                .frame(width: 4)
                .cornerRadius(8)

            VStack(spacing: 8) {
                HStack {
                    Text(title)
                        .fontWeight(.bold)
                        .foregroundColor(accent)
                    Spacer()
                }
                HStack {
                    Text(message)
                    Spacer()
                }
                HStack(spacing: 8) {
                    Spacer()
                    Button(secondaryTitle, action: onSecondary)
                    Button(primaryTitle, action: onPrimary)
                }
            }
            .padding(12)
        }
        .background(Color(white: 0.94))
        .cornerRadius(8)
    }
}
