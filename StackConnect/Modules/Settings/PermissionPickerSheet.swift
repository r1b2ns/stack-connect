import SwiftUI

struct PermissionPickerSheet: View {

    let resource: AccountRuleResource
    let isNil: Bool
    let currentPermissions: [AccountPermission]
    let onDismiss: ([AccountPermission]?) -> Void

    @State private var selected: Set<AccountPermission> = []
    @State private var isNone = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(AccountPermission.allCases, id: \.self) { permission in
                    Button {
                        togglePermission(permission)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: selected.contains(permission) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(selected.contains(permission) ? .accent : .secondary)
                                .font(.title3)

                            Text(permission.displayName)
                                .font(.body)
                                .foregroundStyle(.primary)
                        }
                    }
                }

                // None option
                Button {
                    toggleNone()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: isNone ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(isNone ? .accent : .secondary)
                            .font(.title3)

                        Text(String(localized: "None"))
                            .font(.body)
                            .foregroundStyle(.primary)
                    }
                }
            }
            .navigationTitle(resource.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "OK")) {
                        if isNone {
                            // Explicitly chose None → empty array (not nil)
                            onDismiss([])
                        } else if selected.isEmpty {
                            // Nothing selected at all → nil
                            onDismiss(nil)
                        } else {
                            onDismiss(Array(selected))
                        }
                    }
                }
            }
        }
        .onAppear {
            if isNil {
                // Topic is nil → nothing selected, not even None
                selected = []
                isNone = false
            } else {
                selected = Set(currentPermissions)
                isNone = currentPermissions.isEmpty
            }
        }
    }

    // MARK: - Private

    private func togglePermission(_ permission: AccountPermission) {
        isNone = false
        if selected.contains(permission) {
            selected.remove(permission)
        } else {
            selected.insert(permission)
        }
    }

    private func toggleNone() {
        if isNone {
            isNone = false
        } else {
            isNone = true
            selected.removeAll()
        }
    }
}

// MARK: - Display Names

extension AccountPermission {
    var displayName: String {
        switch self {
        case .view:   return String(localized: "View")
        case .edit:   return String(localized: "Edit")
        case .delete: return String(localized: "Delete")
        case .add:    return String(localized: "Add")
        }
    }
}

extension AccountRuleResource {
    var displayName: String {
        switch self {
        case .apps:       return String(localized: "Apps")
        case .version:    return String(localized: "Versions")
        case .users:      return String(localized: "Users")
        case .review:     return String(localized: "App Review")
        case .testFlight: return String(localized: "TestFlight")
        case .analytics:  return String(localized: "Analytics")
        }
    }

    var footerDescription: String {
        switch self {
        case .apps:       return String(localized: "Manage app listing, metadata, and pricing")
        case .version:    return String(localized: "Manage app versions, builds, and releases")
        case .users:      return String(localized: "Manage team members, roles, and access")
        case .review:     return String(localized: "Submit for review, cancel, and manage review submissions")
        case .testFlight: return String(localized: "Manage beta groups, testers, and builds distribution")
        case .analytics:  return String(localized: "View app analytics, trends, and metrics")
        }
    }
}
