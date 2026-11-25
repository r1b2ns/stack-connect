import SwiftUI

// MARK: - Account row

/// One account in the unified accounts lists (Home › Accounts, Settings ›
/// Accounts): `{store tile} {name / connection · role} ——— [imported] [status] {chevron}`.
/// Render it as the `label` of a button; the tap belongs to the caller.
struct StackAccountRow: View {

    let account: AccountModel
    /// `nil` when the account has no issue (connected): no chip then.
    var status: AccountStatus?
    var showsChevron = true

    var body: some View {
        HStack(spacing: 12) {
            StackIconTile(systemName: account.providerType.iconName, color: account.providerType.color)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(account.name)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if account.origin == .imported {
                StackCapsuleBadge(title: String(localized: "imported"), color: .yellow)
            }

            if let status {
                StackAccountStatusBadge(status: status)
            }

            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
        }
        .contentShape(Rectangle())
    }

    /// "API Key · Admin", "Google Account", ...
    private var subtitle: String {
        [account.connection.title, account.displayedRole?.displayName]
            .compactMap { $0 }
            .joined(separator: " · ")
    }
}

// MARK: - Group header

/// The header of one store's section: its name, the account count and, in
/// Settings › Accounts, an "Add" button that opens the wizard for that store.
struct StackAccountGroupHeader: View {

    let provider: ProviderType
    let count: Int
    var onAdd: (() -> Void)?

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: provider.iconName)
                .foregroundStyle(provider.color)
                .accessibilityHidden(true)
            // One Text so the store name and the count stay on one line
            // ("App Store Connect · 2 accounts"), shrinking a bit before truncating.
            Text(verbatim: "\(provider.displayName) · \(Self.countTitle(count))")
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .layoutPriority(1)
            Spacer(minLength: 8)
            if let onAdd {
                // Icon-only, like the "+" of iOS lists: a titled button took
                // the width the store name needs.
                Button(action: onAdd) {
                    Label(String(localized: "Add", comment: "Settings › Accounts: button in a store's section header that adds an account of that store."),
                          systemImage: "plus.circle.fill")
                        .labelStyle(.iconOnly)
                        .font(.title3)
                        .frame(minWidth: 32, minHeight: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .textCase(nil)
                .accessibilityLabel(Text("Add \(provider.displayName) account",
                                         comment: "VoiceOver label of the Add button of a store's section. The placeholder is the store, e.g. Firebase."))
            }
        }
    }

    /// "No accounts" for 0: CLDR puts 0 in the "one" plural category in some
    /// languages (pt-BR), which would read "0 conta".
    static func countTitle(_ count: Int) -> String {
        guard count > 0 else {
            return String(localized: "No accounts",
                          comment: "Accounts summary (Settings, Home): shown instead of the account count when there are no accounts.")
        }
        return String(localized: "\(count) accounts", comment: "Accounts lists: number of accounts of a store, in its section header.")
    }
}

// MARK: - Groups

/// The store sections of the unified accounts lists: one `Section` per group,
/// with its header (and, in Settings › Accounts, its "Add" button).
struct StackAccountGroupsSections<Row: View>: View {

    let groups: [AccountProviderGroup]
    /// Shows an "Add" button in each header, for that store.
    var onAdd: ((ProviderType) -> Void)?
    @ViewBuilder let row: (AccountModel) -> Row

    var body: some View {
        ForEach(groups) { group in
            Section {
                ForEach(group.accounts) { account in
                    row(account)
                }
            } header: {
                StackAccountGroupHeader(
                    provider: group.provider,
                    count: group.accounts.count,
                    onAdd: onAdd.map { add in { add(group.provider) } }
                )
            }
        }
    }
}

// MARK: - Summary

/// The "Summary" style of the Accounts rows (Settings root, Home): the total,
/// how many need attention (orange) and one chip per store with its count.
struct StackAccountsSummaryView: View {

    let summary: AccountsSummary

    var body: some View {
        HStack(spacing: 12) {
            StackIconTile(systemName: "person.2.fill", color: .blue)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(String(localized: "Accounts"))
                        .font(.body)
                        .foregroundStyle(.primary)
                    Text(StackAccountGroupHeader.countTitle(summary.total))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if summary.needsAttention > 0 {
                    Label {
                        Text("\(summary.needsAttention) need attention",
                             comment: "Accounts summary: how many accounts are disconnected or need an action.")
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                    }
                    .font(.caption)
                    .foregroundStyle(.orange)
                }

                if !summary.providers.isEmpty {
                    buildChips()
                }
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private func buildChips() -> some View {
        HStack(spacing: 6) {
            ForEach(summary.providers) { item in
                HStack(spacing: 4) {
                    Image(systemName: item.provider.iconName)
                        .foregroundStyle(item.provider.color)
                    Text(verbatim: "\(item.count)")
                        .foregroundStyle(.primary)
                }
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(item.provider.color.opacity(0.12), in: Capsule())
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("\(item.provider.displayName): \(item.count)",
                                         comment: "VoiceOver label of a store chip of the accounts summary. Arguments: the store, then its account count."))
            }
        }
    }
}

#Preview {
    List {
        StackAccountsSummaryView(summary: AccountsSummary(
            total: 5,
            needsAttention: 1,
            providers: [.init(provider: .apple, count: 3), .init(provider: .firebase, count: 2)]
        ))
        Section {
            StackAccountRow(account: AccountModel(name: "Acme Apps", providerType: .apple, role: .admin))
            StackAccountRow(account: AccountModel(name: "Personal", providerType: .apple, authMethod: .appleIdSignIn),
                            status: AccountStatus(issues: [.signInExpired]))
        } header: {
            StackAccountGroupHeader(provider: .apple, count: 2, onAdd: {})
        }
    }
}
