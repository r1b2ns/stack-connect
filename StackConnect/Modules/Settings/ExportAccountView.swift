import SwiftUI

struct ExportAccountView: View {

    let account: AccountModel
    let onExport: (String, AccountRules, String) -> URL?
    let onDismiss: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var exportName: String = ""
    @State private var password: String = ""
    @State private var confirmPassword: String = ""
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
            SecureField(String(localized: "Password"), text: $password)
                .textContentType(.newPassword)

            SecureField(String(localized: "Confirm Password"), text: $confirmPassword)
                .textContentType(.newPassword)
        } header: {
            Text(String(localized: "Encryption"))
        } footer: {
            if !password.isEmpty && !confirmPassword.isEmpty && password != confirmPassword {
                Text(String(localized: "Passwords do not match."))
                    .foregroundStyle(.red)
            } else {
                Text(String(localized: "The exported file will be encrypted. You will need this password to import the account."))
            }
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
        let passwordValid = !password.isEmpty && password == confirmPassword
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

        _ = onExport(exportName, rules, password)
    }
}

// MARK: - AccountRuleResource + Identifiable

extension AccountRuleResource: Identifiable {
    var id: String { rawValue }
}
