import SwiftUI

struct CustomizeWidgetsView<ViewModel: HomeViewModelProtocol>: View {

    @ObservedObject var viewModel: ViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var isEditing = false

    var body: some View {
        NavigationStack {
            List {
                buildActiveSection()
                buildAvailableSection()
            }
            .navigationTitle(String(localized: "Customize Widgets"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { buildToolbar() }
            .environment(\.editMode, .constant(isEditing ? .active : .inactive))
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private func buildActiveSection() -> some View {
        Section {
            if viewModel.uiState.widgets.isEmpty {
                buildEmptyActiveRow()
            } else {
                ForEach(viewModel.uiState.widgets, id: \.id) { widget in
                    buildActiveRow(kind: widget.kind, id: widget.id)
                }
                .onDelete { indexSet in
                    for index in indexSet {
                        let widget = viewModel.uiState.widgets[index]
                        viewModel.removeWidget(id: widget.id)
                    }
                }
                .onMove { source, destination in
                    viewModel.moveWidgets(from: source, to: destination)
                }
            }
        } header: {
            Text(String(localized: "Active"))
        }
    }

    @ViewBuilder
    private func buildAvailableSection() -> some View {
        let available = viewModel.availableWidgetKinds()
        if !available.isEmpty {
            Section {
                ForEach(available) { kind in
                    Button {
                        viewModel.addWidget(kind)
                    } label: {
                        buildAvailableRow(kind: kind)
                    }
                    .foregroundStyle(.primary)
                }
            } header: {
                Text(String(localized: "Add Widgets"))
            }
        }
    }

    // MARK: - Rows

    private func buildActiveRow(kind: HomeWidgetKind, id: UUID) -> some View {
        HStack(spacing: 12) {
            buildIcon(kind: kind)
            VStack(alignment: .leading, spacing: 2) {
                Text(kind.displayName)
                    .font(.body)
                    .fontWeight(.medium)
                Text(kind.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }

    private func buildAvailableRow(kind: HomeWidgetKind) -> some View {
        HStack(spacing: 12) {
            buildIcon(kind: kind)
            VStack(alignment: .leading, spacing: 2) {
                Text(kind.displayName)
                    .font(.body)
                    .fontWeight(.medium)
                Text(kind.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "plus.circle.fill")
                .font(.title3)
                .foregroundStyle(.blue)
        }
        .padding(.vertical, 4)
    }

    private func buildIcon(kind: HomeWidgetKind) -> some View {
        Image(systemName: kind.systemImage)
            .font(.title3)
            .foregroundStyle(.white)
            .frame(width: 36, height: 36)
            .background(kind.tintColor)
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func buildEmptyActiveRow() -> some View {
        HStack(spacing: 8) {
            Image(systemName: "rectangle.dashed")
                .foregroundStyle(.tertiary)
            Text(String(localized: "No active widgets"))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private func buildToolbar() -> some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            if !viewModel.uiState.widgets.isEmpty {
                Button(isEditing ? String(localized: "Done") : String(localized: "Edit")) {
                    isEditing.toggle()
                }
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button(String(localized: "Close")) {
                dismiss()
            }
        }
    }
}
