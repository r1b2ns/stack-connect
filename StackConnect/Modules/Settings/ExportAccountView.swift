import SwiftUI
import UIKit

struct ExportAccountView: View {

    let account: AccountModel
    let onExport: (String, AccountRules, String, Date?) -> URL?
    let onDismiss: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var exportName: String = ""
    @State private var password: String = ""
    @State private var confirmPassword: String = ""
    @State private var revealPassword = false
    @State private var revealConfirmPassword = false
    @State private var passwordCopied = false
    @State private var generateConfirmed = false
    @State private var copyConfirmed = false
    @State private var enableExpiration = false

    private let minPasswordLength = 12
    @State private var expirationDate = Calendar.current.date(byAdding: .day, value: 30, to: Date()) ?? Date()
    /// nil = not configured; [] = explicitly None; [.view, ...] = selected
    @State private var permissions: [AccountRuleResource: [AccountPermission]?] = [:]
    @State private var editingResource: AccountRuleResource?

    private let resources: [AccountRuleResource] = [
        .apps, .version, .review, .testFlight, .analytics, .users, .provisioning
    ]

    var body: some View {
        NavigationStack {
            Form {
                buildInfoSection()
                buildNameSection()

                Section {
                } header: {
                    Text(String(localized: "Permissions"))
                }

                ForEach(resources, id: \.self) { resource in
                    buildResourceSection(resource)
                }

                buildPasswordSection()
                buildExpirationSection()
            }
            .navigationTitle(String(localized: "Export Account"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { buildToolbar() }
            .sheet(item: $editingResource) { resource in
                let isNil = isResourceNil(resource)
                let current = permissionsFor(resource)
                PermissionPickerSheet(
                    resource: resource,
                    isNil: isNil,
                    currentPermissions: current
                ) { result in
                    if let selected = result {
                        permissions[resource] = .some(selected)
                    } else {
                        permissions[resource] = .some(nil)
                    }
                    editingResource = nil
                }
                .presentationDetents([.medium])
            }
        }
        .onAppear {
            exportName = account.name
            for resource in resources {
                permissions[resource] = .some(nil)
            }
        }
    }

    // MARK: - Sections

    private func buildInfoSection() -> some View {
        Section {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "person.2.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.blue)

                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "Share access with your team"))
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    Text(String(localized: "Exporting an account is a convenient way to distribute app access to other users in your team. Recipients can import the encrypted file with the password you set, and use the account with the permissions you select below."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func buildNameSection() -> some View {
        Section {
            TextField(String(localized: "Account Name"), text: $exportName)
                .textContentType(.name)
        } header: {
            Text(String(localized: "Name"))
        }
    }

    private func buildResourceSection(_ resource: AccountRuleResource) -> some View {
        Section {
            Button {
                editingResource = resource
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(resource.displayName)
                            .font(.body)
                            .foregroundStyle(.primary)

                        Text(subtitleForResource(resource))
                            .font(.caption)
                            .foregroundColor(isResourceNil(resource) ? .secondary : .accentColor)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .foregroundStyle(.primary)
        } footer: {
            Text(resource.footerDescription)
        }
    }

    private func buildPasswordSection() -> some View {
        Section {
            HStack {
                Group {
                    if revealPassword {
                        TextField(String(localized: "Password"), text: $password)
                    } else {
                        SecureField(String(localized: "Password"), text: $password)
                    }
                }
                .textContentType(.newPassword)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)

                Button {
                    revealPassword.toggle()
                } label: {
                    Image(systemName: revealPassword ? "eye.slash" : "eye")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(revealPassword
                    ? String(localized: "Hide password")
                    : String(localized: "Show password"))
            }

            HStack {
                Group {
                    if revealConfirmPassword {
                        TextField(String(localized: "Confirm Password"), text: $confirmPassword)
                    } else {
                        SecureField(String(localized: "Confirm Password"), text: $confirmPassword)
                    }
                }
                .textContentType(.newPassword)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)

                Button {
                    revealConfirmPassword.toggle()
                } label: {
                    Image(systemName: revealConfirmPassword ? "eye.slash" : "eye")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(revealConfirmPassword
                    ? String(localized: "Hide password")
                    : String(localized: "Show password"))
            }

            Button {
                let generated = AccountCrypto.generateStrongPassword()
                password = generated
                confirmPassword = generated
                revealPassword = true
                UIPasteboard.general.string = generated
                passwordCopied = true
                triggerConfirmation($generateConfirmed)
            } label: {
                HStack {
                    Image(systemName: generateConfirmed ? "checkmark.circle.fill" : "wand.and.stars")
                        .foregroundStyle(generateConfirmed ? .green : .accentColor)
                    Text(String(localized: "Generate strong password"))
                }
            }

            Button {
                UIPasteboard.general.string = password
                passwordCopied = true
                triggerConfirmation($copyConfirmed)
            } label: {
                HStack {
                    Image(systemName: copyConfirmed ? "checkmark.circle.fill" : "doc.on.doc")
                        .foregroundStyle(copyConfirmed ? .green : .accentColor)
                    Text(String(localized: "Copy password"))
                }
            }
            .disabled(password.isEmpty)
        } header: {
            Text(String(localized: "Encryption"))
        } footer: {
            buildPasswordFooter()
        }
    }

    @ViewBuilder
    private func buildPasswordFooter() -> some View {
        if !password.isEmpty && !confirmPassword.isEmpty && password != confirmPassword {
            Text(String(localized: "Passwords do not match."))
                .foregroundStyle(.red)
        } else if !password.isEmpty && password.count < minPasswordLength {
            Text(String(localized: "Use at least \(minPasswordLength) characters. Tip: tap \"Generate strong password\" for a secure one."))
                .foregroundStyle(.orange)
        } else if passwordCopied {
            Text(String(localized: "The password was copied to your clipboard. Share it with your team securely — you will need it to import the account."))
                .foregroundStyle(.green)
        } else {
            Text(String(localized: "The exported file will be encrypted. You will need this password to import the account."))
        }
    }

    /// Momentarily shows a green checkmark on the button and fires a success haptic.
    private func triggerConfirmation(_ flag: Binding<Bool>) {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        withAnimation { flag.wrappedValue = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation { flag.wrappedValue = false }
        }
    }

    private func buildExpirationSection() -> some View {
        Section {
            Toggle(String(localized: "Set expiration date"), isOn: $enableExpiration)

            if enableExpiration {
                DatePicker(
                    String(localized: "Expiration Date"),
                    selection: $expirationDate,
                    in: Date()...,
                    displayedComponents: [.date]
                )
            }
        } header: {
            Text(String(localized: "Expiration"))
        } footer: {
            Text(String(localized: "When set, the imported account will stop working after this date and will become inaccessible. The recipient must request a new file."))
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private func buildToolbar() -> some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button(String(localized: "Cancel")) {
                dismiss()
                onDismiss()
            }
        }

        ToolbarItem(placement: .confirmationAction) {
            Button(String(localized: "Export")) {
                performExport()
            }
            .disabled(!isExportEnabled)
        }
    }

    // MARK: - Helpers

    private func isResourceNil(_ resource: AccountRuleResource) -> Bool {
        guard let value = permissions[resource] else { return true }
        return value == nil
    }

    private func permissionsFor(_ resource: AccountRuleResource) -> [AccountPermission] {
        guard let value = permissions[resource], let perms = value else { return [] }
        return perms
    }

    private var isExportEnabled: Bool {
        let nameValid = !exportName.trimmingCharacters(in: .whitespaces).isEmpty
        let allResourcesConfigured = resources.allSatisfy { !isResourceNil($0) }
        let passwordValid = password.count >= minPasswordLength && password == confirmPassword
        return nameValid && allResourcesConfigured && passwordValid
    }

    private func subtitleForResource(_ resource: AccountRuleResource) -> String {
        if isResourceNil(resource) {
            return String(localized: "Not configured")
        }
        let perms = permissionsFor(resource)
        if perms.isEmpty {
            return String(localized: "None")
        }
        return perms.map(\.displayName).joined(separator: ", ")
    }

    private func performExport() {
        let rules = AccountRules(
            apps: permissionsFor(.apps),
            version: permissionsFor(.version),
            users: permissionsFor(.users),
            review: permissionsFor(.review),
            testFlight: permissionsFor(.testFlight),
            analytics: permissionsFor(.analytics),
            provisioning: permissionsFor(.provisioning)
        )

        _ = onExport(exportName, rules, password, enableExpiration ? expirationDate : nil)
    }
}

// MARK: - AccountRuleResource + Identifiable

extension AccountRuleResource: Identifiable {
    var id: String { rawValue }
}
