import SwiftUI

// MARK: - Credentials

/// The `.configFile` Credentials component of an import: the `.scexport` file
/// and the password it was encrypted with (the file picker is presented by
/// the wizard's coordinator).
struct AccountWizardImportCredentialsView: View {

    @Binding var importFile: AccountWizardImportState
    let onPickFile: () -> Void
    let onShowTutorial: () -> Void

    var body: some View {
        Section {
            HStack(spacing: 12) {
                StackIconTile(
                    systemName: importFile.fileURL == nil ? "doc" : "checkmark",
                    color: importFile.fileURL == nil ? .gray : .green
                )
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text("File", comment: "Account wizard import: the .scexport file row.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(importFile.fileName ?? String(localized: "No file chosen", comment: "Account wizard import: no .scexport file picked yet."))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 8)

                StackTrackedButton(.importFile, on: .accountWizardCredentials) {
                    onPickFile()
                } label: {
                    Text(importFile.fileURL == nil
                         ? String(localized: "Choose", comment: "Account wizard import: picks the .scexport file.")
                         : String(localized: "Change", comment: "Account wizard import: picks another .scexport file."))
                }
                .buttonStyle(.bordered)
            }

            SecureField(String(localized: "File Password", comment: "Account wizard import: the password the .scexport file was encrypted with."),
                        text: $importFile.password)
                .textContentType(.password)
        } footer: {
            Text("Enter the password used to encrypt this file.")
        }

        Section {
            StackTrackedButton(.howToImport, on: .accountWizardCredentials) {
                onShowTutorial()
            } label: {
                Label(String(localized: "How to import?"), systemImage: "questionmark.circle")
            }
        }
    }
}

// MARK: - Review

/// Review of an import: the name to import it under.
struct AccountWizardImportReview: View {

    @Binding var importFile: AccountWizardImportState

    var body: some View {
        Section {
            TextField(String(localized: "Account Name"), text: $importFile.accountName)
                .textContentType(.name)
        } header: {
            Text("Name", comment: "Account wizard review: the account name field.")
        } footer: {
            Text("Choose a name for this account.")
        }

        AccountWizardSummarySection(rows: [
            .init(title: String(localized: "Type", comment: "Account wizard review: the account type."),
                  value: AccountWizardCopy.title(of: .importFile)),
            .init(title: String(localized: "File", comment: "Account wizard import: the .scexport file row."),
                  value: importFile.fileName ?? ""),
            .init(title: String(localized: "Stored", comment: "Account wizard review: where the credentials are kept."),
                  value: AccountWizardCopy.storage(of: .scexportFile, savesPassword: false))
        ])
    }
}

// MARK: - Summary

/// The facts of the Review step ("Type", "Connection", "Stored"...).
struct AccountWizardSummarySection: View {

    struct Row: Identifiable {
        let title: String
        let value: String
        var id: String { title }
    }

    let rows: [Row]

    var body: some View {
        Section {
            ForEach(rows) { row in
                LabeledContent(row.title) {
                    Text(row.value)
                        .multilineTextAlignment(.trailing)
                }
            }
        } header: {
            Text("Summary", comment: "Account wizard review: the facts of what will be added.")
        }
    }
}
