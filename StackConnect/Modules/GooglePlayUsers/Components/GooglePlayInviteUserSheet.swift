import SwiftUI

/// Invites a person to the Google Play developer account (plan U6, prototype 21).
struct GooglePlayInviteUserSheet: View {

    /// The account's apps in scope (App Access picker).
    let apps: [GooglePlayAppItem]
    /// Account-wide permissions are allowed (not a scoped import).
    let allowsAccountPermissions: Bool
    /// Sends the invitation; returns a user-facing error, `nil` on success.
    let onSend: (GooglePlayInviteForm) async -> String?

    @State private var form = GooglePlayInviteForm()
    @State private var isSending = false
    @State private var error: String?
    @State private var showExpiry = false
    @State private var grantEditor: GooglePlayGrantEditorRequest?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.analytics) private var analytics

    var body: some View {
        NavigationStack {
            Form {
                buildUserSection()
                if allowsAccountPermissions {
                    buildPresetSection()
                    buildAccountPermissionsSection()
                }
                buildAppAccessSection()

                if let error {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .font(.subheadline)
                    }
                }

                Section {
                    Text("Google emails the invitation. The user appears as “Invited” until they accept; an invitation that isn't accepted expires and can be sent again.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(String(localized: "Invite User"))
            .navigationBarTitleDisplayMode(.inline)
            .trackScreen(.googlePlayInviteUser)
            .disabled(isSending)
            .toolbar { buildToolbar() }
            .sheet(isPresented: $showExpiry) {
                GooglePlayAccessExpirySheet(initial: form.expiration) { form.expiration = $0 }
            }
            .sheet(item: $grantEditor) { request in
                buildAppPermissionsSheet(request)
            }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private func buildToolbar() -> some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            StackTrackedButton(String(localized: "Cancel"), button: .cancel, on: .googlePlayInviteUser) { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
            if isSending {
                ProgressView()
            } else {
                Button(String(localized: "Send")) {
                    analytics.track(.buttonTap(.send, on: .googlePlayInviteUser))
                    Task {
                        isSending = true
                        error = await onSend(form)
                        isSending = false
                        if error == nil { dismiss() }
                    }
                }
                .fontWeight(.semibold)
                .disabled(!form.canSend)
            }
        }
    }

    // MARK: - Sections

    private func buildUserSection() -> some View {
        Section {
            LabeledContent(String(localized: "Email")) {
                // Verbatim: a localized key would turn the address into a link.
                TextField(String(localized: "Email"), text: $form.email, prompt: Text(verbatim: "name@example.com"))
                    .multilineTextAlignment(.trailing)
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            }
            GooglePlayAccessExpiryRow(expiration: form.expiration) {
                analytics.track(.buttonTap(.accessExpiry, on: .googlePlayInviteUser))
                showExpiry = true
            }
        } header: {
            Text("User Information")
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                if let reason = form.blockingReason {
                    Text(reason).foregroundStyle(.red)
                }
                Text("Must be a Google account. Google Play doesn't ask for a name: it comes from the person's Google account once they accept.")
            }
        }
    }

    private func buildPresetSection() -> some View {
        Section {
            StackFilterChips(
                items: GooglePlayPermissionPreset.allCases,
                selection: form.preset,
                title: \.title
            ) { preset in
                analytics.track(.buttonTap(.preset, on: .googlePlayInviteUser))
                form.apply(preset)
            }
        } header: {
            Text("Role Preset")
        } footer: {
            Text("Presets only pre-fill the toggles below. Google Play has no roles, just permissions.")
        }
    }

    private func buildAccountPermissionsSection() -> some View {
        Section {
            Toggle(GooglePlayPermissionCatalog.adminName, isOn: Binding(
                get: { form.isAdmin },
                set: { form.setAdmin($0) }
            ))
            GooglePlayAccountPermissionRows(values: form.accountPermissions, isEditable: true) { permission, isOn in
                form.set(permission, isOn: isOn)
            }
        } header: {
            Text("Account Permissions · All Apps")
        } footer: {
            Text("Admin grants every permission for every app, including managing users.")
        }
    }

    private func buildAppAccessSection() -> some View {
        Section {
            ForEach(form.grants) { grant in
                Button {
                    grantEditor = GooglePlayGrantEditorRequest(packageName: grant.packageName, permissions: grant.appLevelPermissions)
                } label: {
                    HStack(spacing: 12) {
                        let app = apps.first { $0.packageName == grant.packageName }
                        GooglePlayAppIconView(app: app, size: 32)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(app?.displayName ?? grant.packageName)
                                .fontWeight(.medium)
                                .foregroundStyle(.primary)
                            Text(grant.summary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        form.removeGrant(packageName: grant.packageName)
                    } label: {
                        Label(String(localized: "Remove"), systemImage: "minus.circle")
                    }
                }
            }
        } header: {
            HStack {
                Text("App Access (\(form.grants.count))")
                Spacer()
                if !availableApps.isEmpty {
                    Button(String(localized: "Add App")) {
                        analytics.track(.buttonTap(.add, on: .googlePlayInviteUser))
                        grantEditor = GooglePlayGrantEditorRequest(packageName: nil, permissions: [])
                    }
                    .font(.subheadline)
                    .textCase(nil)
                }
            }
        } footer: {
            Text("App permissions apply to one app only. A user with no account permission and no app sees nothing.")
        }
    }

    private var availableApps: [GooglePlayAppItem] {
        apps.filter { app in !form.grants.contains { $0.packageName == app.packageName } }
    }

    private func buildAppPermissionsSheet(_ request: GooglePlayGrantEditorRequest) -> some View {
        GooglePlayAppPermissionsSheet(
            form: GooglePlayGrantForm(packageName: request.packageName, values: request.permissions,
                                      accountValues: form.accountPermissions),
            apps: availableApps,
            editedApp: request.packageName.flatMap { packageName in apps.first { $0.packageName == packageName } },
            onSave: { packageName, values in
                form.setGrant(packageName: packageName, values: values)
                return true
            },
            onRemove: request.packageName.map { packageName in
                {
                    form.removeGrant(packageName: packageName)
                    return true
                }
            }
        )
    }
}
