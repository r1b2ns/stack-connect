import SwiftUI

/// Multi-select picker for scoping an export to a subset of the account's apps.
/// Modeled on `PermissionPickerSheet`. Selection is by app **bundle id** (stable,
/// human-readable, unique within a team) — the package name for Google Play
/// apps. An empty selection is treated by the caller as "all apps" (no
/// restriction) — see the backward-compat contract.
struct AppsPermissionPickerSheet: View {

    let apps: [ExportableApp]
    let initiallySelected: Set<String>
    let onDismiss: (Set<String>) -> Void

    @State private var selected: Set<String> = []
    @State private var searchQuery = ""

    /// Apps filtered by the current search query (name OR bundle id, case-insensitive).
    /// A blank query returns the full `apps` set.
    private var filteredApps: [ExportableApp] {
        guard !searchQuery.trimmingCharacters(in: .whitespaces).isEmpty else {
            return apps
        }

        return apps.filter { app in
            app.name.localizedCaseInsensitiveContains(searchQuery)
                || app.bundleId.localizedCaseInsensitiveContains(searchQuery)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(filteredApps, id: \.id) { app in
                    let isSelected = selected.contains(app.bundleId)

                    Button {
                        toggle(app.bundleId)
                    } label: {
                        HStack(spacing: 12) {
                            StackAppIcon(url: app.iconURL, size: 44, cornerRadius: 10)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(app.name)
                                    .font(.body)
                                    .foregroundStyle(.primary)

                                Text(app.bundleId)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(isSelected ? .accent : .secondary)
                                .font(.title3)
                        }
                    }
                }
            }
            .searchable(
                text: $searchQuery,
                prompt: String(localized: "Search apps")
            )
            .navigationTitle(String(localized: "Apps permissions"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if selected.count == apps.count {
                        Button(String(localized: "Select None")) {
                            selected.removeAll()
                        }
                    } else {
                        Button(String(localized: "Select All")) {
                            selected = Set(apps.map(\.bundleId))
                        }
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "OK")) {
                        onDismiss(selected)
                    }
                }
            }
        }
        .onAppear {
            selected = initiallySelected
        }
    }

    // MARK: - Private

    private func toggle(_ bundleId: String) {
        if selected.contains(bundleId) {
            selected.remove(bundleId)
        } else {
            selected.insert(bundleId)
        }
    }
}
