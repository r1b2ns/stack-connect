import SwiftUI

struct ExportAccountView: View {

    let account: AccountModel
    let onExport: (String, AccountRules) -> URL?
    let onDismiss: () -> Void

    @State private var exportName: String = ""
    /// nil = not configured; [] = explicitly None; [.view, ...] = selected
    @State private var permissions: [AccountRuleResource: [AccountPermission]?] = [:]
    @State private var editingResource: AccountRuleResource?

    private let resources: [AccountRuleResource] = [
        .apps, .version, .review, .testFlight, .analytics, .users
    ]

    var body: some View {
        NavigationStack {
            Form {
                buildNameSection()

                Section {
                } header: {
                    Text(String(localized: "Permissions"))
                }

                ForEach(resources, id: \.self) { resource in
                    buildResourceSection(resource)
                }
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
                        // User chose something (permissions or None)
                        permissions[resource] = .some(selected)
                    } else {
                        // User chose nothing → back to nil
                        permissions[resource] = .some(nil)
                    }
                    editingResource = nil
                }
                .presentationDetents([.medium])
            }
        }
        .onAppear {
            exportName = account.name
            // All resources start as nil (not configured)
            for resource in resources {
                permissions[resource] = .some(nil)
            }
        }
    }

    // MARK: - Sections

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

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private func buildToolbar() -> some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button(String(localized: "Cancel")) {
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
        return nameValid && allResourcesConfigured
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
            analytics: permissionsFor(.analytics)
        )

        _ = onExport(exportName, rules)
    }
}

// MARK: - AccountRuleResource + Identifiable

extension AccountRuleResource: Identifiable {
    var id: String { rawValue }
}

