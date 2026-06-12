import Foundation
import SwiftCrossUI
import StackHomeCore
import StackProtocols
import WindowsAppCore

// Phase 4 · Block F · T-F07 — the accounts list screen (US-W01 / US-W06).
//
// Renders the full account list for a single provider: toolbar with back/title/
// add button, loading/empty/populated states, and a 2-column grid of vertical
// cards. Each card has a ⋮ button that opens a DesktopAlertView modal with
// "Open" and "Delete" actions.
//
// The view binds to `WindowsAccountsListModel` (T-F06) which owns the accounts
// array, loading/error state, and the delete confirmation flow.

struct WindowsAccountsListView: View {

    let provider: ProviderType
    @State private var coordinator: WindowsHomeCoordinator
    @State private var model: WindowsAccountsListModel

    /// When `false`, the "< Back" button is hidden (inline sidebar usage).
    let showBackButton: Bool

    init(
        provider: ProviderType,
        coordinator: WindowsHomeCoordinator,
        storage: PersistentStorable,
        secrets: KeyStorable,
        showBackButton: Bool = true
    ) {
        self.provider = provider
        self.showBackButton = showBackButton
        _coordinator = State(wrappedValue: coordinator)
        _model = State(wrappedValue: WindowsAccountsListModel(
            providerType: provider,
            storage: storage,
            secrets: secrets
        ))
    }

    var body: some View {
        ScrollView {
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 16) {
                    toolbar
                    errorBanner
                    content
                    Spacer()
                }
                .padding(16)
                .frame(maxWidth: 860, alignment: .leading)
                Spacer()
            }
        }
        .overlay {
            // ⋮ actions modal
            if model.alertAccountId != nil {
                DesktopAlertView(
                    title: alertTitle,
                    subtitle: "O que gostaria de fazer com esta conta?",
                    options: [
                        DesktopAlertOption("Open", color: .blue),
                        DesktopAlertOption("Delete", color: .red),
                    ],
                    onClose: { model.alertAccountId = nil },
                    onSelect: { label in handleAlertSelection(label) }
                )
            }
        }
        .overlay {
            // Delete confirmation modal
            if model.deleteConfirmingId != nil {
                DesktopAlertView(
                    title: deleteAlertTitle,
                    options: [
                        DesktopAlertOption("Delete", color: .red),
                        DesktopAlertOption("Cancel", color: .gray),
                    ],
                    onClose: { model.cancelDelete() },
                    onSelect: { label in handleDeleteConfirmation(label) }
                )
            }
        }
        .task {
            await model.loadAccounts()
        }
    }

    // MARK: - Alert helpers

    private var alertTitle: String {
        guard let id = model.alertAccountId,
              let account = model.accounts.first(where: { $0.id == id }) else {
            return "Options"
        }
        return account.name
    }

    private var deleteAlertTitle: String {
        guard let id = model.deleteConfirmingId,
              let account = model.accounts.first(where: { $0.id == id }) else {
            return "Delete account?"
        }
        return "Delete \"\(account.name)\"? This cannot be undone."
    }

    private func handleAlertSelection(_ label: String) {
        guard let id = model.alertAccountId,
              let account = model.accounts.first(where: { $0.id == id }) else {
            model.alertAccountId = nil
            return
        }
        model.alertAccountId = nil

        switch label {
        case "Open":
            openAccount(account)
        case "Delete":
            model.expiredTappedId = nil
            model.confirmDelete(id: id)
        default:
            break
        }
    }

    /// Opens an account: navigates to its apps list, or — when the account has
    /// expired — toggles the inline "expired" error instead of navigating.
    /// Shared by the card tap (US-W06) and the "Open" menu item so both behave
    /// identically.
    private func openAccount(_ account: AccountModel) {
        if account.isExpired {
            model.expiredTappedId = (model.expiredTappedId == account.id) ? nil : account.id
        } else {
            model.expiredTappedId = nil
            coordinator.push(.appsList(accountId: account.id, accountName: account.name))
        }
    }

    private func handleDeleteConfirmation(_ label: String) {
        switch label {
        case "Delete":
            Task { await model.executeDelete() }
        default:
            model.cancelDelete()
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        VStack(spacing: 12) {
            HStack {
                if showBackButton {
                    WindowsBackButtonView(onBack: { coordinator.pop() })
                }
                Spacer()
                Button("+ Add") {
                    coordinator.push(.addAccountOptions(provider))
                }
            }
            HStack {
                Text(provider.displayName)
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
            }
        }
    }

    // MARK: - Error banner

    @ViewBuilder
    private var errorBanner: some View {
        if let message = model.errorMessage {
            HStack(spacing: 0) {
                Rectangle()
                    .fill(Color.red)
                    .frame(width: 4)
                    .cornerRadius(8)

                HStack(spacing: 8) {
                    Text(message)
                        .foregroundColor(.red)
                    Spacer()
                }
                .padding(12)
            }
            .background(Color.gray.opacity(0.15))
            .cornerRadius(8)
        }
    }

    // MARK: - Content states

    @ViewBuilder
    private var content: some View {
        if model.isLoading {
            loadingState
        } else if model.accounts.isEmpty {
            emptyState
        } else {
            populatedState
        }
    }

    private var loadingState: some View {
        HStack(spacing: 8) {
            ProgressView()
            Text("Loading...")
                .foregroundColor(.gray)
            Spacer()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Text("(  +  )")
                .font(.title2)
                .foregroundColor(.gray)
            Text("No Accounts")
                .font(.title2)
                .fontWeight(.semibold)
            Text("Tap \"+ Add\" to add your first account.")
                .foregroundColor(.gray)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Populated state — 2-column grid

    /// Iterates over `model.accounts` directly (proven ForEach pattern) and
    /// renders HStack pairs for even-indexed accounts to form a 2-column grid.
    private var populatedState: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(model.accounts, id: \.id) { account in
                if isRowStart(account) {
                    HStack(alignment: .top, spacing: 12) {
                        accountCard(account)
                        if let pair = pairAccount(for: account) {
                            accountCard(pair)
                        }
                        Spacer()
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Returns `true` if this account is at an even index (start of a grid row).
    private func isRowStart(_ account: AccountModel) -> Bool {
        guard let index = model.accounts.firstIndex(where: { $0.id == account.id }) else {
            return false
        }
        return index % 2 == 0
    }

    /// Returns the next account in the array (the right-side pair), or nil
    /// if this is the last account.
    private func pairAccount(for account: AccountModel) -> AccountModel? {
        guard let index = model.accounts.firstIndex(where: { $0.id == account.id }),
              index + 1 < model.accounts.count else {
            return nil
        }
        return model.accounts[index + 1]
    }

    /// A single account card: vertical layout with provider glyph (centered),
    /// account name, badges, and a ⋮ button that opens the DesktopAlertView.
    private func accountCard(_ account: AccountModel) -> some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                // Top bar with ⋮ button. This row is kept OUTSIDE the tap region
                // below: on the AppKit backend an `.onTapGesture` inserts a
                // transparent target covering its child's bounds that swallows
                // clicks to any Button beneath it — so the ⋮ Button must not sit
                // under the card-open tap region or it would stop receiving taps.
                HStack {
                    Spacer()
                    Button("...") {
                        model.alertAccountId = account.id
                    }
                    .fontWeight(.bold)
                }

                // Tappable content area: glyph + name + badges only (no Buttons),
                // so attaching `.onTapGesture` here opens the account without
                // swallowing any interactive child. Behaves identically to the
                // "Open" menu item via the shared `openAccount(_:)` helper.
                VStack(spacing: 8) {
                    // Provider glyph (centered)
                    Text(providerGlyph)
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundColor(providerColor)
                        .frame(maxWidth: .infinity)

                    // Account name
                    Text(account.name)
                        .fontWeight(.medium)
                        .frame(maxWidth: .infinity)

                    // Badges row
                    HStack(spacing: 4) {
                        badgesView(for: account)
                        Spacer()
                    }
                }
                .onTapGesture { openAccount(account) }
            }
            .padding(10)
            .frame(width: 120, height: 120)
            .background(providerColor.opacity(0.08))
            .cornerRadius(8)
            // Stroke MUST live in `.background` (not `.overlay`): on the AppKit
            // backend an overlaid stroke becomes a sibling path view on top of the
            // card that swallows clicks, blocking the ⋮ button. Behind the
            // translucent fill the border still shows through.
            .background {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(providerColor.opacity(0.4), style: StrokeStyle(width: 1.0))
            }

            // Expired inline error
            if model.expiredTappedId == account.id {
                expiredInlineError(for: account)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Expired inline error

    private func expiredInlineError(for account: AccountModel) -> some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(Color.red)
                .frame(width: 4)
                .cornerRadius(8)

            HStack(spacing: 8) {
                Text("This account has expired. Re-import or delete it.")
                    .foregroundColor(.red)
                Spacer()
            }
            .padding(12)
        }
        .background(Color.gray.opacity(0.15))
        .cornerRadius(8)
    }

    // MARK: - Badges

    @ViewBuilder
    private func badgesView(for account: AccountModel) -> some View {
        if account.origin == .imported {
            badgePill(text: "imported", color: .blue)
        }
        if account.isExpired {
            badgePill(text: "expired", color: .red)
        }
    }

    private func badgePill(text: String, color: Color) -> some View {
        Text(text)
            .foregroundColor(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .cornerRadius(4)
    }

    // MARK: - Provider glyph/color

    private var providerGlyph: String {
        switch provider {
        case .apple:      return "\u{F8FF}"
        case .firebase:   return "\u{1F525}"
        case .googlePlay: return "\u{25B6}"
        }
    }

    private var providerColor: Color {
        HomeGridCell.color(named: provider.colorName)
    }
}
