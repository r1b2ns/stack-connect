import SwiftUI

/// The last screen: what was added (or reconnected), "View in List" and,
/// after adding, "Add Another Account".
struct AccountWizardDoneView: View {

    let result: AccountWizardResult
    let onViewInList: () -> Void
    let onAddAnother: () -> Void

    private var tint: Color { result.provider?.color ?? .accentColor }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(tint)
                    .accessibilityHidden(true)

                Text(AccountWizardCopy.doneTitle(for: result))
                    .font(.title)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)

                if !result.names.isEmpty {
                    buildNames()
                }

                Text(AccountWizardCopy.doneMessage(for: result))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                VStack(spacing: 12) {
                    StackTrackedButton(.viewInList, on: .accountWizardDone) {
                        onViewInList()
                    } label: {
                        Text(result.isReconnect
                             ? String(localized: "Done")
                             : String(localized: "View in List", comment: "Account wizard done screen: closes the wizard on the accounts list."))
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(tint)

                    if !result.isReconnect {
                        Button {
                            onAddAnother()
                        } label: {
                            Text("Add Another Account", comment: "Account wizard done screen: starts the wizard again at the account type.")
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(.top, 8)
            }
            .padding(24)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .background(Color(.systemGroupedBackground))
        .trackScreen(.accountWizardDone)
    }

    private func buildNames() -> some View {
        VStack(spacing: 6) {
            ForEach(result.names, id: \.self) { name in
                Text(name)
                    .font(.body)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color(.secondarySystemGroupedBackground), in: Capsule())
            }
        }
    }
}
