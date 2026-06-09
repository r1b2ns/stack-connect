import Foundation
import SwiftCrossUI
import StackHomeCore
import StackProtocols
import WindowsAppCore

// Phase 4 · Block F · T-F07 — the accounts list screen (US-W01 / US-W06).
//
// Renders the full account list for a single provider: toolbar with back/title/
// add button, loading/empty/populated states, card rows with badges (imported,
// expired), and an inline delete-confirmation banner.
//
// The view binds to `WindowsAccountsListModel` (T-F06) which owns the accounts
// array, loading/error state, and the delete confirmation flow. The view is
// purely declarative — all mutations go through the model's intents.
//
// Layout follows the Windows app convention: content capped at 860px, padded
// 16px, with a `ScrollView` + `VStack`. The toolbar uses `WindowsBackButtonView`
// for the "< Back" action (pops to Home) and a "+ Add" button that pushes the
// `.addAccountOptions(provider)` route.
//
// Delete flow (US-W06): each row has an inline "Delete" button. Tapping it
// calls `model.confirmDelete(id:)` which shows the confirmation banner below
// the row. Confirm executes the cascade delete (account + apps + versions +
// credentials); Cancel dismisses the banner.

struct WindowsAccountsListView: View {

    /// The provider this list displays — drives the title and "+ Add" route.
    let provider: ProviderType
    /// Navigation coordinator — Back pops, "+ Add" pushes the add-account route.
    @State private var coordinator: WindowsHomeCoordinator

    /// The accounts list model. Observed via `@State` so the view redraws when
    /// the model's `@Published` properties change.
    @State private var model: WindowsAccountsListModel

    /// When non-nil, the expired-account inline error is shown for this account
    /// id (US-W01 AC-6 / TC-F014). Tapping an expired row sets this instead of
    /// navigating; tapping it again or tapping a different row clears it.
    @State private var expiredTappedId: String? = nil

    init(
        provider: ProviderType,
        coordinator: WindowsHomeCoordinator,
        storage: PersistentStorable,
        secrets: KeyStorable
    ) {
        self.provider = provider
        _coordinator = State(wrappedValue: coordinator)
        _model = State(wrappedValue: WindowsAccountsListModel(
            providerType: provider,
            storage: storage,
            secrets: secrets
        ))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                toolbar
                errorBanner
                content
                Spacer()
            }
            .padding(16)
            .frame(maxWidth: 860)
        }
        .task {
            await model.loadAccounts()
        }
    }

    // MARK: - Toolbar (US-W01 AC-7 / AC-8)

    /// Header row: "< Back" on the left, provider title centered, "+ Add" on the
    /// right. Back pops to Home (AC-7); "+ Add" pushes the add-account options
    /// screen for this provider (AC-8).
    private var toolbar: some View {
        VStack(spacing: 12) {
            HStack {
                WindowsBackButtonView(onBack: { coordinator.pop() })
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

    // MARK: - Error banner (US-W06 AC-5)

    /// Inline error banner shown when an operation (load or delete) fails.
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
            .background(Color(white: 0.94))
            .cornerRadius(8)
        }
    }

    // MARK: - Content: loading / empty / populated (US-W01 AC-2 / AC-3 / AC-4)

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

    // MARK: - Loading state (US-W01 AC-4)

    /// An inline loading indicator shown while the model fetches accounts.
    private var loadingState: some View {
        HStack(spacing: 8) {
            ProgressView()
            Text("Loading...")
                .foregroundColor(.gray)
            Spacer()
        }
    }

    // MARK: - Empty state (US-W01 AC-3)

    /// Centered empty-state message when no accounts exist for this provider.
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

    // MARK: - Populated state (US-W01 AC-2 / AC-5 / AC-6, US-W06)

    /// The scrollable list of account rows, each with badges and delete controls.
    private var populatedState: some View {
        VStack(spacing: 12) {
            ForEach(model.accounts, id: \.id) { account in
                accountCard(account)
            }
        }
    }

    /// A single account row: glyph + name + badges + disclosure chevron + Delete.
    /// If this account is in the delete-confirming state, the confirmation banner
    /// appears directly below the card. If the account is expired and was tapped,
    /// an inline error is shown instead of navigating (US-W01 AC-6).
    private func accountCard(_ account: AccountModel) -> some View {
        VStack(spacing: 0) {
            // Main row
            HStack(spacing: 12) {
                // Provider glyph
                Text(providerGlyph)
                    .fontWeight(.bold)
                    .foregroundColor(providerColor)

                // Account name
                Text(account.name)
                    .fontWeight(.medium)

                Spacer()

                // Badges (US-W01 AC-5 / AC-6)
                badgesView(for: account)

                // Disclosure chevron
                Text(">")
                    .foregroundColor(.gray)

                // Inline Delete button (US-W06 AC-1)
                Button("Delete") {
                    expiredTappedId = nil
                    model.confirmDelete(id: account.id)
                }
                .foregroundColor(.red)
            }
            .padding(16)
            .background(providerColor.opacity(0.08))
            .cornerRadius(8)
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(providerColor.opacity(0.4), style: StrokeStyle(width: 1.0))
            }
            .onTapGesture {
                if account.isExpired {
                    // US-W01 AC-6 / TC-F014: tapping an expired row shows an
                    // inline error instead of navigating. If a delete
                    // confirmation is showing for this row, dismiss it first.
                    if model.deleteConfirmingId == account.id {
                        model.cancelDelete()
                    }
                    expiredTappedId = (expiredTappedId == account.id) ? nil : account.id
                } else {
                    // T-W10: non-expired account — navigate to the Apps List
                    // for this account (design §2.3: Accounts list → appsList).
                    // Nit-2: clear any lingering expired-account error banner
                    // before navigating, so it does not persist on back.
                    expiredTappedId = nil
                    coordinator.push(.appsList(
                        accountId: account.id,
                        accountName: account.name
                    ))
                }
            }

            // Expired inline error (US-W01 AC-6)
            if expiredTappedId == account.id {
                expiredInlineError(for: account)
            }

            // Delete confirmation banner (US-W06 AC-2 / AC-3 / AC-4)
            if model.deleteConfirmingId == account.id {
                deleteConfirmationBanner(for: account)
            }
        }
    }

    // MARK: - Expired inline error (US-W01 AC-6)

    /// An inline error banner shown below the row when an expired account is
    /// tapped, instead of navigating (TC-F014).
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
        .background(Color(white: 0.94))
        .cornerRadius(8)
    }

    // MARK: - Badges (US-W01 AC-5 / AC-6)

    @ViewBuilder
    private func badgesView(for account: AccountModel) -> some View {
        if account.origin == .imported {
            badgePill(text: "imported", color: .blue)
        }
        if account.isExpired {
            badgePill(text: "expired", color: .red)
        }
    }

    /// A small colored pill badge with text.
    private func badgePill(text: String, color: Color) -> some View {
        Text(text)
            .foregroundColor(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .cornerRadius(4)
    }

    // MARK: - Delete confirmation banner (US-W06 AC-2 / AC-3 / AC-4)

    /// The inline confirmation banner: warning icon + message + Cancel/Delete
    /// buttons. Confirm executes the cascade delete; Cancel dismisses.
    private func deleteConfirmationBanner(for account: AccountModel) -> some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(Color.orange)
                .frame(width: 4)
                .cornerRadius(8)

            VStack(spacing: 8) {
                HStack {
                    Text("Delete \"\(account.name)\"? This cannot be undone.")
                        .fontWeight(.medium)
                    Spacer()
                }
                HStack(spacing: 8) {
                    Spacer()
                    Button("Cancel") {
                        model.cancelDelete()
                    }
                    Button("Delete") {
                        Task {
                            await model.executeDelete()
                        }
                    }
                    .foregroundColor(.red)
                }
            }
            .padding(12)
        }
        .background(Color(white: 0.94))
        .cornerRadius(8)
    }

    // MARK: - Provider glyph/color (consistent with WindowsProviderCardView)

    /// The text glyph for this provider, matching the Home card convention.
    private var providerGlyph: String {
        switch provider {
        case .apple:      return "ASC"
        case .firebase:   return "\u{1F525}" // fire emoji
        case .googlePlay: return "\u{25B6}" // play triangle
        }
    }

    /// The tint color for this provider, matching the Home card convention.
    private var providerColor: Color {
        HomeGridCell.color(named: provider.colorName)
    }
}
