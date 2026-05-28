import SwiftUI
import UniformTypeIdentifiers

// MARK: - Factory

@MainActor
struct ImportDevicesViewFactory {
    static func build(account: AccountModel) -> some View {
        ImportDevicesEntry(account: account)
    }
}

// MARK: - Entry

private struct ImportDevicesEntry: View {
    @StateObject private var coordinator = ImportDevicesCoordinator()
    @StateObject private var viewModel: ImportDevicesViewModel

    init(account: AccountModel) {
        _viewModel = StateObject(wrappedValue: ImportDevicesViewModel(account: account))
    }

    var body: some View {
        ImportDevicesView(viewModel: viewModel)
            .environmentObject(coordinator)
    }
}

// MARK: - File picker types

private extension UTType {
    static var deviceIds: UTType {
        UTType(filenameExtension: "deviceids") ?? .data
    }
}

// MARK: - View

struct ImportDevicesView<ViewModel: ImportDevicesViewModelProtocol>: View {

    @ObservedObject var viewModel: ViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var isImporting = false

    var body: some View {
        Group {
            switch viewModel.uiState.step {
            case .pickFile:  buildPickFile()
            case .preview:   buildPreview()
            case .importing: buildImporting()
            case .done:      buildDone()
            }
        }
        .navigationTitle(String(localized: "Import Devices"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if viewModel.uiState.step == .done {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "Done")) { dismiss() }
                }
            }
        }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.deviceIds, .plainText, .text, .data],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    Task { await viewModel.loadFile(from: url) }
                }
            case .failure(let error):
                Log.print.error("[ImportDevices] File picker failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Step 1: Pick file

    private func buildPickFile() -> some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "square.and.arrow.down.on.square")
                .font(.system(size: 72))
                .foregroundStyle(.blue)

            VStack(spacing: 6) {
                Text(String(localized: "Bulk Import"))
                    .font(.title2)
                    .fontWeight(.semibold)

                Text(String(localized: "Choose a .deviceids file (Apple bulk format) or a .txt with one UDID per line."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Button {
                isImporting = true
            } label: {
                Label(String(localized: "Choose File"), systemImage: "folder")
                    .frame(maxWidth: 240)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)

            if let error = viewModel.uiState.errorMessage {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            Spacer()

            buildFormatHelp()
                .padding(.horizontal)
                .padding(.bottom, 24)
        }
    }

    private func buildFormatHelp() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(String(localized: "Supported formats"), systemImage: "info.circle")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            Text(String(localized: "• .deviceids — XML plist with key 'Device UDIDs'\n• .txt — header row plus UDID, Name, Platform separated by tab or comma"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Step 2: Preview

    private func buildPreview() -> some View {
        VStack(spacing: 0) {
            List {
                Section {
                    if let name = viewModel.uiState.sourceFileName {
                        HStack {
                            Image(systemName: "doc")
                            Text(name).font(.subheadline)
                        }
                    }
                    HStack {
                        Text(String(localized: "Parsed"))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(viewModel.uiState.parsed.count)")
                    }
                    HStack {
                        Text(String(localized: "Valid"))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(viewModel.uiState.validParsedCount)")
                    }
                    HStack {
                        Text(String(localized: "Selected"))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(viewModel.uiState.selectedCount)")
                    }
                }

                Section {
                    Picker(String(localized: "Default Platform"), selection: $viewModel.uiState.platformRaw) {
                        Text(String(localized: "iOS, tvOS, watchOS, visionOS")).tag("IOS")
                        Text(String(localized: "macOS")).tag("MAC_OS")
                    }
                } header: {
                    Text(String(localized: "Platform"))
                } footer: {
                    Text(String(localized: "Used when the file does not specify a platform per row."))
                        .font(.caption)
                }

                Section {
                    HStack {
                        Button(String(localized: "Select All")) {
                            viewModel.selectAll()
                        }
                        Spacer()
                        Button(String(localized: "Deselect All"), role: .destructive) {
                            viewModel.deselectAll()
                        }
                    }
                    .font(.subheadline)

                    ForEach(viewModel.uiState.parsed) { device in
                        buildPreviewRow(device)
                    }
                } header: {
                    Text(String(localized: "Devices"))
                }

                if let error = viewModel.uiState.errorMessage {
                    Section {
                        Text(error).font(.footnote).foregroundStyle(.red)
                    }
                }
            }

            VStack(spacing: 12) {
                Button {
                    Task { await viewModel.startImport() }
                } label: {
                    HStack {
                        Text(String(localized: "Register \(viewModel.uiState.selectedCount) device(s)"))
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(viewModel.uiState.selectedCount > 0 ? Color.blue : Color.gray.opacity(0.3))
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(viewModel.uiState.selectedCount == 0)

                Button(String(localized: "Choose Another File")) {
                    viewModel.reset()
                }
                .foregroundStyle(.secondary)
            }
            .padding()
        }
    }

    private func buildPreviewRow(_ device: ParsedDevice) -> some View {
        let isSelected = viewModel.uiState.selectedIds.contains(device.id)
        return Button {
            viewModel.toggle(id: device.id)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.blue : Color.gray)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(device.name.isEmpty
                             ? String(localized: "(no name)")
                             : device.name)
                            .font(.body)
                            .fontWeight(.medium)
                            .foregroundStyle(.primary)

                        if !device.looksValid {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }
                    }

                    Text(device.udid)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .font(.system(.caption, design: .monospaced))

                    if let hint = device.platformHint {
                        Text(hint)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                Spacer()
            }
        }
        .disabled(!device.looksValid)
        .foregroundStyle(.primary)
    }

    // MARK: - Step 3: Importing

    private func buildImporting() -> some View {
        VStack(spacing: 20) {
            Spacer()
            ProgressView(value: Double(viewModel.uiState.importedCount + viewModel.uiState.failures.count),
                         total: Double(viewModel.uiState.totalToImport))
                .progressViewStyle(.linear)
                .frame(maxWidth: 280)

            Text(String(localized: "Registering \(viewModel.uiState.importedCount + viewModel.uiState.failures.count) of \(viewModel.uiState.totalToImport)…"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding()
    }

    // MARK: - Step 4: Done

    private func buildDone() -> some View {
        List {
            Section {
                HStack(spacing: 14) {
                    Image(systemName: viewModel.uiState.failures.isEmpty
                          ? "checkmark.seal.fill"
                          : "exclamationmark.triangle.fill")
                        .font(.largeTitle)
                        .foregroundStyle(viewModel.uiState.failures.isEmpty ? .green : .orange)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(String(localized: "Import finished"))
                            .font(.headline)
                        Text(String(localized: "\(viewModel.uiState.importedCount) succeeded, \(viewModel.uiState.failures.count) failed"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            if !viewModel.uiState.failures.isEmpty {
                Section {
                    ForEach(viewModel.uiState.failures) { failure in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.red)
                                Text(failure.name.isEmpty ? String(localized: "(no name)") : failure.name)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                            }
                            Text(failure.udid)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                            Text(failure.message)
                                .font(.caption)
                                .foregroundStyle(.red)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.vertical, 2)
                    }
                } header: {
                    Text(String(localized: "Failures"))
                }
            }

            Section {
                Button(String(localized: "Import Another File")) {
                    viewModel.reset()
                }
            }
        }
    }
}
