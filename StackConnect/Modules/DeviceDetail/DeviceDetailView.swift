import SwiftUI

// MARK: - Factory

@MainActor
struct DeviceDetailViewFactory {
    static func build(account: AccountModel, device: DeviceModel) -> some View {
        DeviceDetailEntry(account: account, device: device)
    }
}

// MARK: - Entry

private struct DeviceDetailEntry: View {
    @StateObject private var coordinator = DeviceDetailCoordinator()
    @StateObject private var viewModel: DeviceDetailViewModel

    init(account: AccountModel, device: DeviceModel) {
        _viewModel = StateObject(wrappedValue: DeviceDetailViewModel(account: account, device: device))
    }

    var body: some View {
        DeviceDetailView(viewModel: viewModel)
            .environmentObject(coordinator)
    }
}

// MARK: - View

struct DeviceDetailView<ViewModel: DeviceDetailViewModelProtocol>: View {

    @ObservedObject var viewModel: ViewModel

    @State private var editedName = ""

    private var device: DeviceModel {
        viewModel.uiState.device
    }

    private var nameChanged: Bool {
        editedName.trimmingCharacters(in: .whitespacesAndNewlines) != device.name &&
        !editedName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        List {
            buildNameSection()
            buildStatusSection()
            buildDetailsSection()

            if let error = viewModel.uiState.errorMessage {
                Section {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle(device.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { editedName = device.name }
    }

    // MARK: - Sections

    private func buildNameSection() -> some View {
        Section {
            TextField(String(localized: "Name"), text: $editedName)

            if nameChanged {
                Button {
                    Task {
                        let ok = await viewModel.rename(to: editedName)
                        if ok { editedName = viewModel.uiState.device.name }
                    }
                } label: {
                    HStack {
                        Text(String(localized: "Save Name"))
                        Spacer()
                        if viewModel.uiState.isRenaming {
                            ProgressView()
                        }
                    }
                }
                .disabled(viewModel.uiState.isRenaming)
            }
        } header: {
            Text(String(localized: "Name"))
        }
    }

    private func buildStatusSection() -> some View {
        Section {
            HStack {
                Circle()
                    .fill(device.isEnabled ? Color.green : Color.gray)
                    .frame(width: 8, height: 8)
                Text(device.isEnabled ? String(localized: "Enabled") : String(localized: "Disabled"))
                Spacer()
                if viewModel.uiState.isTogglingStatus {
                    ProgressView()
                } else {
                    Button(device.isEnabled
                           ? String(localized: "Disable")
                           : String(localized: "Enable")
                    ) {
                        Task { await viewModel.toggleStatus() }
                    }
                    .foregroundStyle(device.isEnabled ? Color.red : Color.green)
                }
            }
            .disabled(viewModel.uiState.isTogglingStatus)
        } header: {
            Text(String(localized: "Status"))
        } footer: {
            Text(String(localized: "Devices cannot be deleted via the API — they can only be disabled. Disabled devices still count toward the team device limit until the next membership year."))
                .font(.caption)
        }
    }

    private func buildDetailsSection() -> some View {
        Section {
            if let udid = device.udid {
                buildRow(label: String(localized: "UDID"), value: udid, monospaced: true)
            }
            buildRow(label: String(localized: "Device Class"), value: device.deviceClassDisplayName)
            if let model = device.model {
                buildRow(label: String(localized: "Model"), value: model)
            }
            buildRow(label: String(localized: "Platform"), value: device.platformDisplayName)
            if let addedDate = device.addedDate {
                buildRow(
                    label: String(localized: "Registered"),
                    value: addedDate.formatted(date: .abbreviated, time: .omitted)
                )
            }
            buildRow(label: String(localized: "ID"), value: device.id)
        } header: {
            Text(String(localized: "Details"))
        }
    }

    private func buildRow(label: String, value: String, monospaced: Bool = false) -> some View {
        HStack(alignment: .top) {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
                .modifier(MonospacedIfNeeded(monospaced: monospaced))
        }
        .font(.subheadline)
    }
}

private struct MonospacedIfNeeded: ViewModifier {
    let monospaced: Bool
    func body(content: Content) -> some View {
        if monospaced {
            content.font(.system(.subheadline, design: .monospaced))
        } else {
            content
        }
    }
}
