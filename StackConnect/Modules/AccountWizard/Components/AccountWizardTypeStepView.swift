import SwiftUI

// MARK: - Type step

/// Step 1: the stores this build offers (Google Play only while
/// `googlePlayAccounts` is ON), then "Other ways" with the import.
struct AccountWizardTypeStepView: View {

    let config: AccountWizardConfig
    let onChoose: (AccountWizardKind) -> Void

    var body: some View {
        Section {
            ForEach(config.providerKinds) { kind in
                buildRow(kind)
            }
        }

        if let importKind = config.importKind {
            Section {
                buildRow(importKind, showsMethods: false)
            } header: {
                Text("Other Ways", comment: "Account wizard, Type step: section with the import of a .scexport file.")
            }
        }
    }

    private func buildRow(_ kind: AccountWizardKindConfig, showsMethods: Bool = true) -> some View {
        Button {
            onChoose(kind.kind)
        } label: {
            HStack(spacing: 12) {
                StackIconTile(
                    systemName: AccountWizardCopy.systemImage(of: kind.kind),
                    color: kind.kind.provider?.color ?? .gray,
                    size: 36
                )
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(AccountWizardCopy.title(of: kind.kind))
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(AccountWizardCopy.subtitle(of: kind.kind))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if showsMethods {
                        Text(AccountWizardCopy.methodsLabel(of: kind))
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.footnote)
                    .fontWeight(.semibold)
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Method step

/// Step 2 (only with more than one method): every method as an equal card,
/// none promoted over another (no "Recommended" badge). Neutral glyphs: the
/// email and password method never shows the Apple logo.
struct AccountWizardMethodStepView: View {

    let kind: AccountWizardKindConfig
    let selected: AccountWizardMethod?
    let onChoose: (AccountWizardMethod) -> Void

    var body: some View {
        ForEach(kind.methods) { method in
            if let connectionMethod = method.connectionMethod, let provider = kind.kind.provider {
                Section {
                    Button {
                        onChoose(method)
                    } label: {
                        StackOptionCard(
                            systemImage: connectionMethod.systemImage,
                            tint: provider.color,
                            title: connectionMethod.title,
                            message: connectionMethod.summary(for: provider)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected == method ? .isSelected : [])
                }
            }
        }
    }
}

// MARK: - How It Works

/// The credentials explainer (PR #109, flag `accountConnectionGuide`): how
/// StackConnect handles the credentials, and the guide again.
struct AccountWizardHowItWorksSection: View {

    let onOpen: () -> Void

    var body: some View {
        Section {
            Button(action: onOpen) {
                StackListRow(
                    icon: "lock.shield.fill",
                    iconColor: .blue,
                    title: String(localized: "How It Works"),
                    subtitle: String(localized: "How StackConnect handles your credentials",
                                     comment: "Add Account: subtitle of the entry that opens the connection guide.")
                )
            }
            .foregroundStyle(.primary)
            .accessibilityLabel(Text("How It Works"))
            .accessibilityHint(Text("How StackConnect handles your credentials"))
        }
    }
}
