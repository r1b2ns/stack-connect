import SwiftUI

struct PermissionPickerSheet: View {

    let resource: AccountRuleResource
    let isNil: Bool
    let currentPermissions: [AccountPermission]
    let onDismiss: ([AccountPermission]?) -> Void

    @State private var selected: Set<AccountPermission> = []
    @State private var isNone = false

    /// Permissions that are implicitly enabled by higher-level ones and cannot be deselected
    private var impliedPermissions: Set<AccountPermission> {
        var implied = Set<AccountPermission>()
        // add → implies edit + view
        if selected.contains(.add) {
            implied.insert(.edit)
            implied.insert(.view)
        }
        // delete → implies edit + view
        if selected.contains(.delete) {
            implied.insert(.edit)
            implied.insert(.view)
        }
        // edit → implies view
        if selected.contains(.edit) {
            implied.insert(.view)
        }
        return implied
    }

    /// All effectively active permissions (explicit + implied)
    private var effectivePermissions: Set<AccountPermission> {
        selected.union(impliedPermissions)
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(AccountPermission.allCases, id: \.self) { permission in
                    let isActive = effectivePermissions.contains(permission)
                    let isLocked = impliedPermissions.contains(permission)

                    Button {
                        if !isLocked {
                            togglePermission(permission)
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(isActive ? (isLocked ? .gray : .accent) : .secondary)
                                .font(.title3)

                            Text(permission.displayName)
                                .font(.body)
                                .foregroundStyle(isLocked ? .secondary : .primary)
                        }
                    }
                    .disabled(isLocked)
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
                            onDismiss([])
                        } else if selected.isEmpty && impliedPermissions.isEmpty {
                            onDismiss(nil)
                        } else {
                            onDismiss(Array(effectivePermissions))
                        }
                    }
                }
            }
        }
        .onAppear {
            if isNil {
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
            // When removing a high-level permission, also remove it from explicit
            // but implied ones stay if another high-level still requires them
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
        case .review:     return String(localized: "Review and Rating")
        case .testFlight:   return String(localized: "TestFlight")
        case .analytics:    return String(localized: "Analytics")
        case .provisioning: return String(localized: "Certificates, Identifiers, Devices & Profiles")
        }
    }

    var footerDescription: String {
        switch self {
        case .apps:         return String(localized: "Manage app listing, metadata, and pricing")
        case .version:      return String(localized: "Manage app versions, builds, and releases")
        case .users:        return String(localized: "Manage team members, roles, and access")
        case .review:       return String(localized: "Manager and reply user's app review")
        case .testFlight:   return String(localized: "Manage beta groups, testers, and builds distribution")
        case .analytics:    return String(localized: "View app analytics, trends, and metrics")
        case .provisioning: return String(localized: "Manage certificates, identifiers, devices, and provisioning profiles")
        }
    }
}
