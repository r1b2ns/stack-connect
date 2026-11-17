import SwiftUI

/// The account-level permission toggles of the user detail and the invite
/// sheet (prototypes 17 / 21): the common ones always, every permission that is
/// on, and the rest behind "More Permissions" so the list stays short.
struct GooglePlayAccountPermissionRows: View {

    /// Draft account-level values (Admin included).
    let values: [String]
    let isEditable: Bool
    let onToggle: (GooglePlayPermission, Bool) -> Void

    @State private var showsMore = false
    /// Permissions on when the screen opened: they stay in the short list, so
    /// toggling one never moves a row.
    @State private var initiallyOn: Set<String>

    init(values: [String], isEditable: Bool, onToggle: @escaping (GooglePlayPermission, Bool) -> Void) {
        self.values = values
        self.isEditable = isEditable
        self.onToggle = onToggle
        _initiallyOn = State(initialValue: Set(GooglePlayPermissionCatalog.accountPermissions
            .filter { GooglePlayPermissionCatalog.contains($0, in: values, level: .account) }
            .map(\.id)))
    }

    var body: some View {
        ForEach(primary) { permission in
            buildToggle(permission)
        }
        if !more.isEmpty {
            DisclosureGroup(isExpanded: $showsMore) {
                ForEach(more) { permission in
                    buildToggle(permission)
                }
            } label: {
                Text("More Permissions (\(more.count))")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func state(_ permission: GooglePlayPermission) -> GooglePlayPermissionCatalog.Effective {
        GooglePlayPermissionCatalog.accountState(of: permission, in: values)
    }

    /// The common permissions plus any on when the screen opened, in catalog order.
    private var primary: [GooglePlayPermission] {
        GooglePlayPermissionCatalog.accountPermissions.filter { permission in
            GooglePlayPermissionCatalog.commonAccountPermissionIds.contains(permission.id)
                || initiallyOn.contains(permission.id)
        }
    }

    private var more: [GooglePlayPermission] {
        let shown = Set(primary.map(\.id))
        return GooglePlayPermissionCatalog.accountPermissions.filter { !shown.contains($0.id) }
    }

    private func buildToggle(_ permission: GooglePlayPermission) -> some View {
        let effective = state(permission)
        return Toggle(permission.accountName, isOn: Binding(
            get: { effective != .off },
            set: { onToggle(permission, $0) }
        ))
        .disabled(effective == .implied || !isEditable)
    }
}
