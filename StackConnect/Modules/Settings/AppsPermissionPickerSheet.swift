import SwiftUI

/// Multi-select picker for scoping an export to a subset of the account's apps.
/// Modeled on `PermissionPickerSheet`. Selection is by app **bundle id** (stable,
/// human-readable, unique within a team). An empty selection is treated by the
/// caller as "all apps" (no restriction) — see the backward-compat contract.
struct AppsPermissionPickerSheet: View {

    let apps: [AppModel]
    let initiallySelected: Set<String>
    let onDismiss: (Set<String>) -> Void

    @State private var selected: Set<String> = []
    @State private var searchQuery = ""

    /// Apps filtered by the current search query (name OR bundle id, case-insensitive).
    /// A blank query returns the full `apps` set.
    private var filteredApps: [AppModel] {
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

                    StackTrackedButton(.toggleApp, on: .appsPermissionPicker) {
                        toggle(app.bundleId)
                    } label: {
                        HStack(spacing: 12) {
                            buildAppIcon(url: app.iconUrl.flatMap { URL(string: $0) })

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
            .trackScreen(.appsPermissionPicker)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if selected.count == apps.count {
                        StackTrackedButton(String(localized: "Select None"), button: .selectNone, on: .appsPermissionPicker) {
                            selected.removeAll()
                        }
                    } else {
                        StackTrackedButton(String(localized: "Select All"), button: .selectAll, on: .appsPermissionPicker) {
                            selected = Set(apps.map(\.bundleId))
                        }
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    StackTrackedButton(String(localized: "OK"), button: .ok, on: .appsPermissionPicker) {
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

    // MARK: - App Icon

    private func buildAppIcon(url: URL?) -> some View {
        Group {
            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        appIconPlaceholder
                    case .empty:
                        ProgressView()
                            .frame(width: 44, height: 44)
                    @unknown default:
                        appIconPlaceholder
                    }
                }
            } else {
                appIconPlaceholder
            }
        }
        .frame(width: 44, height: 44)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var appIconPlaceholder: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(Color.blue.opacity(0.15))
            .overlay {
                Image(systemName: "app.fill")
                    .foregroundStyle(.blue)
                    .font(.title3)
            }
    }
}
