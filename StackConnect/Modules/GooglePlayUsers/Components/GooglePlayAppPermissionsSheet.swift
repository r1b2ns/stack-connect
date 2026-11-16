import SwiftUI

// MARK: - Form

/// The choices of the App Permissions sheet (plan U7), kept apart from the
/// view so the rules are testable: one app (picked when adding, fixed when
/// editing), app-level toggles, implied permissions locked on.
struct GooglePlayGrantForm: Equatable {

    /// The app; `nil` until one is picked when adding.
    var packageName: String?
    /// App-level values (raw, unknown ones kept).
    var values: [String]
    /// The user's account-wide values: they apply to this app too and lock the
    /// matching toggles on.
    let accountValues: [String]
    /// Editing an existing grant: the app can't change.
    let isEditing: Bool

    init(packageName: String?, values: [String], accountValues: [String]) {
        self.packageName = packageName
        self.values = values
        self.accountValues = accountValues
        self.isEditing = packageName != nil
    }

    func state(of permission: GooglePlayPermission) -> GooglePlayPermissionCatalog.Effective {
        GooglePlayPermissionCatalog.appState(of: permission, appValues: values, accountValues: accountValues)
    }

    mutating func set(_ permission: GooglePlayPermission, isOn: Bool) {
        guard state(of: permission) != .implied else { return }
        values = GooglePlayPermissionCatalog.setting(permission, on: isOn, in: values, level: .app)
    }

    /// What is saved: "View app information" added when anything else is on.
    var normalizedValues: [String] {
        GooglePlayPermissionCatalog.normalized(values, level: .app)
    }

    /// An app is picked and at least one permission is on.
    var canSave: Bool {
        packageName != nil && !normalizedValues.isEmpty
    }
}

// MARK: - Sheet

/// Grants or edits one user's access to one app (prototype 22). Shared by the
/// user detail (saves right away) and the invite sheet (keeps a draft).
struct GooglePlayAppPermissionsSheet: View {

    /// Apps offered when adding (in scope, without access yet).
    let apps: [GooglePlayAppItem]
    /// Icon and name of the app being edited.
    let editedApp: GooglePlayAppItem?
    let onSave: (_ packageName: String, _ values: [String]) async -> Bool
    /// `nil` hides "Remove Access to This App" (adding, or not allowed).
    let onRemove: (() async -> Bool)?

    @State private var form: GooglePlayGrantForm
    @State private var isSaving = false
    @State private var confirmRemove = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.analytics) private var analytics

    init(
        form: GooglePlayGrantForm,
        apps: [GooglePlayAppItem],
        editedApp: GooglePlayAppItem?,
        onSave: @escaping (_ packageName: String, _ values: [String]) async -> Bool,
        onRemove: (() async -> Bool)?
    ) {
        _form = State(initialValue: form)
        self.apps = apps
        self.editedApp = editedApp
        self.onSave = onSave
        self.onRemove = onRemove
    }

    var body: some View {
        NavigationStack {
            Form {
                buildAppSection()
                ForEach(GooglePlayPermissionCatalog.grouped(.app), id: \.group) { group in
                    Section {
                        ForEach(group.permissions) { permission in
                            let state = form.state(of: permission)
                            Toggle(permission.appName, isOn: Binding(
                                get: { state != .off },
                                set: { form.set(permission, isOn: $0) }
                            ))
                            .disabled(state == .implied)
                        }
                    } header: {
                        Text(group.group.title)
                    } footer: {
                        if group.group == GooglePlayPermissionGroup.allCases.last {
                            Text("“View app information” is always included with any other permission. Permissions the user already has for all apps are shown on and can't be turned off here.")
                        }
                    }
                }
                buildOtherSection()
                if let onRemove {
                    Section {
                        Button(role: .destructive) {
                            confirmRemove = true
                        } label: {
                            Text("Remove Access to This App")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .alert(String(localized: "Remove Access"), isPresented: $confirmRemove) {
                        Button(String(localized: "Remove"), role: .destructive) {
                            Task {
                                isSaving = true
                                let removed = await onRemove()
                                isSaving = false
                                if removed { dismiss() }
                            }
                        }
                        StackTrackedButton(String(localized: "Cancel"), button: .cancel, on: .googlePlayAppPermissions, role: .cancel) {}
                    } message: {
                        Text("The user loses access to this app right away.")
                    }
                }
            }
            .navigationTitle(String(localized: "App Permissions"))
            .navigationBarTitleDisplayMode(.inline)
            .trackScreen(.googlePlayAppPermissions)
            .disabled(isSaving)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    StackTrackedButton(String(localized: "Cancel"), button: .cancel, on: .googlePlayAppPermissions) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button(String(localized: "Save")) {
                            guard let packageName = form.packageName else { return }
                            analytics.track(.buttonTap(.save, on: .googlePlayAppPermissions))
                            Task {
                                isSaving = true
                                let saved = await onSave(packageName, form.normalizedValues)
                                isSaving = false
                                if saved { dismiss() }
                            }
                        }
                        .fontWeight(.semibold)
                        .disabled(!form.canSave)
                    }
                }
            }
        }
    }

    // MARK: - App

    @ViewBuilder
    private func buildAppSection() -> some View {
        Section {
            if form.isEditing {
                buildAppRow(editedApp, packageName: form.packageName ?? "", isSelected: true)
            } else if apps.isEmpty {
                Text("Every app of this account already has access set for this user.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(apps) { app in
                    Button {
                        analytics.track(.buttonTap(.select, on: .googlePlayAppPermissions))
                        form.packageName = app.packageName
                    } label: {
                        buildAppRow(app, packageName: app.packageName, isSelected: form.packageName == app.packageName)
                    }
                    .buttonStyle(.plain)
                }
            }
        } header: {
            Text("App")
        } footer: {
            if !form.isEditing {
                Text("Pick one app. Its permissions apply to that app only.")
            }
        }
    }

    private func buildAppRow(_ app: GooglePlayAppItem?, packageName: String, isSelected: Bool) -> some View {
        HStack(spacing: 12) {
            GooglePlayAppIconView(app: app, size: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(app?.displayName ?? packageName)
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
                Text(packageName)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isSelected {
                Image(systemName: "checkmark")
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.accentColor)
            }
        }
        .contentShape(Rectangle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private func buildOtherSection() -> some View {
        let unknown = GooglePlayPermissionCatalog.unknownValues(in: form.values)
        if !unknown.isEmpty {
            Section {
                ForEach(unknown, id: \.self) { value in
                    LabeledContent(GooglePlayPermissionCatalog.displayName(forUnknown: value)) {
                        Image(systemName: "checkmark").foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Other", comment: "Google Play permissions StackConnect doesn't know (kept as they are).")
            }
        }
    }
}
