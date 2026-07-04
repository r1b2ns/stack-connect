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

    var body: some View {
        NavigationStack {
            List {
                ForEach(apps, id: \.id) { app in
                    let isSelected = selected.contains(app.bundleId)

                    Button {
                        toggle(app.bundleId)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(isSelected ? .accent : .secondary)
                                .font(.title3)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(app.name)
                                    .font(.body)
                                    .foregroundStyle(.primary)

                                Text(app.bundleId)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
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
