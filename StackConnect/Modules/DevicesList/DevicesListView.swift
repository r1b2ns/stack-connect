import SwiftUI

// MARK: - Factory

@MainActor
struct DevicesListViewFactory {
    static func build(account: AccountModel) -> some View {
        DevicesListEntry(account: account)
    }
}

// MARK: - Entry

private struct DevicesListEntry: View {
    @StateObject private var coordinator = DevicesListCoordinator()
    @StateObject private var viewModel: DevicesListViewModel

    init(account: AccountModel) {
        _viewModel = StateObject(wrappedValue: DevicesListViewModel(account: account))
    }

    var body: some View {
        DevicesListView(viewModel: viewModel)
            .environmentObject(coordinator)
    }
}

// MARK: - View

struct DevicesListView<ViewModel: DevicesListViewModelProtocol>: View {

    @ObservedObject var viewModel: ViewModel
    @EnvironmentObject private var homeCoordinator: HomeCoordinator
    @State private var showCreate = false

    var body: some View {
        buildContent()
            .navigationTitle(String(localized: "Devices"))
            .navigationBarTitleDisplayMode(.inline)
            .searchable(
                text: $viewModel.uiState.searchQuery,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: String(localized: "Search devices")
            )
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            showCreate = true
                        } label: {
                            Label(String(localized: "Register Device"), systemImage: "plus")
                        }
                        Button {
                            homeCoordinator.navigateToImportDevices(viewModel.uiState.account)
                        } label: {
                            Label(String(localized: "Import from File"), systemImage: "square.and.arrow.down")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel(String(localized: "Add Devices"))
                }
            }
            .task { await viewModel.load() }
            .refreshable { await viewModel.load() }
            .sheet(isPresented: $showCreate) {
                CreateDeviceSheet(viewModel: viewModel)
            }
            .onReceive(NotificationCenter.default.publisher(for: .deviceUpdated)) { notification in
                if let model = notification.object as? DeviceModel {
                    viewModel.upsert(model)
                }
            }
    }

    @ViewBuilder
    private func buildContent() -> some View {
        if viewModel.uiState.isLoading && viewModel.uiState.devices.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.uiState.filtered.isEmpty {
            buildEmptyState()
        } else {
            buildList()
        }
    }

    @ViewBuilder
    private func buildEmptyState() -> some View {
        if !viewModel.uiState.searchQuery.isEmpty {
            ContentUnavailableView.search(text: viewModel.uiState.searchQuery)
        } else {
            ContentUnavailableView {
                Label(String(localized: "No Devices"), systemImage: "iphone.gen3")
            } description: {
                if let error = viewModel.uiState.errorMessage {
                    Text(error)
                } else {
                    Text(String(localized: "No devices registered for this account."))
                }
            }
        }
    }

    private func buildList() -> some View {
        List {
            ForEach(viewModel.uiState.filtered) { device in
                Button {
                    homeCoordinator.navigateToDeviceDetail(
                        device: device,
                        account: viewModel.uiState.account
                    )
                } label: {
                    buildRow(device)
                }
                .foregroundStyle(.primary)
            }
        }
    }

    private func buildRow(_ device: DeviceModel) -> some View {
        HStack(spacing: 12) {
            Image(systemName: iconName(for: device.deviceClass))
                .font(.title3)
                .foregroundStyle(device.isEnabled ? Color.blue : Color.gray)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(device.name)
                    .font(.body)
                    .fontWeight(.medium)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(device.deviceClassDisplayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Circle()
                        .fill(device.isEnabled ? Color.green : Color.gray)
                        .frame(width: 5, height: 5)

                    Text(device.isEnabled ? String(localized: "Enabled") : String(localized: "Disabled"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }

    private func iconName(for deviceClass: String?) -> String {
        switch deviceClass {
        case "IPHONE":           return "iphone.gen3"
        case "IPAD":             return "ipad"
        case "IPOD":             return "ipodtouch"
        case "APPLE_TV":         return "appletv"
        case "APPLE_WATCH":      return "applewatch"
        case "APPLE_VISION_PRO": return "visionpro"
        case "MAC":              return "macbook"
        default:                 return "rectangle.on.rectangle"
        }
    }
}

// MARK: - Create sheet

private struct CreateDeviceSheet<ViewModel: DevicesListViewModelProtocol>: View {

    @ObservedObject var viewModel: ViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var udid = ""
    @State private var platformRaw = "IOS"

    private let platforms = [
        (raw: "IOS",    label: String(localized: "iOS, tvOS, watchOS, visionOS")),
        (raw: "MAC_OS", label: String(localized: "macOS"))
    ]

    private var canSubmit: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        !udid.trimmingCharacters(in: .whitespaces).isEmpty &&
        !viewModel.uiState.isCreating
    }

    @ViewBuilder
    private func buildUDIDTutorialSection() -> some View {
        Section {
            buildTutorialBlock(
                icon: "macbook.and.iphone",
                title: String(localized: "From a Mac (Finder)"),
                steps: [
                    String(localized: "Connect the iPhone or iPad to a Mac with a cable and unlock it"),
                    String(localized: "Open Finder and select the device in the sidebar"),
                    String(localized: "Click the line under the device name (capacity / iOS version) — it cycles between Serial Number, UDID and ECID"),
                    String(localized: "Right-click the UDID and choose Copy")
                ]
            )

            buildTutorialBlock(
                icon: "hammer",
                title: String(localized: "From Xcode"),
                steps: [
                    String(localized: "Connect the device and open Xcode"),
                    String(localized: "Menu Window → Devices and Simulators"),
                    String(localized: "Select the device on the left and copy the Identifier field")
                ]
            )

            buildTutorialBlock(
                icon: "safari",
                title: String(localized: "From the device itself"),
                steps: [
                    String(localized: "On the iPhone or iPad open Safari and go to a UDID provider you trust (e.g. udid.tech, get.udid.io)"),
                    String(localized: "Install the configuration profile when prompted (Settings → Profile Downloaded)"),
                    String(localized: "After the profile installs, the page reloads and shows the UDID for you to copy")
                ]
            )
        } header: {
            Text(String(localized: "How to find the UDID"))
        } footer: {
            Text(String(localized: "The UDID is a 25-character (modern devices) or 40-character hexadecimal identifier. iOS Settings no longer show it directly — one of the methods above is required."))
                .font(.caption)
        }
    }

    private func buildTutorialBlock(icon: String, title: String, steps: [String]) -> some View {
        let shareText = Self.makeShareText(title: title, steps: steps)

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundStyle(.blue)
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
                ShareLink(item: shareText) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.subheadline)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(String(localized: "Share \(title)"))
            }

            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(index + 1).")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 16, alignment: .trailing)
                        Text(step)
                            .font(.caption)
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.leading, 4)
        }
        .padding(.vertical, 4)
    }

    private static func makeShareText(title: String, steps: [String]) -> String {
        var lines: [String] = [title, ""]
        for (index, step) in steps.enumerated() {
            lines.append("\(index + 1). \(step)")
        }
        return lines.joined(separator: "\n")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(String(localized: "Device name"), text: $name)
                } header: {
                    Text(String(localized: "Name"))
                }

                Section {
                    Picker(String(localized: "Platform"), selection: $platformRaw) {
                        ForEach(platforms, id: \.raw) { platform in
                            Text(platform.label).tag(platform.raw)
                        }
                    }
                } header: {
                    Text(String(localized: "Platform"))
                }

                Section {
                    HStack(spacing: 8) {
                        TextField(String(localized: "UDID"), text: $udid)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(.system(.body, design: .monospaced))

                        PasteButton(payloadType: String.self) { strings in
                            if let value = strings.first {
                                udid = value.trimmingCharacters(in: .whitespacesAndNewlines)
                            }
                        }
                        .labelStyle(.iconOnly)
                        .buttonBorderShape(.capsule)
                    }
                } header: {
                    Text(String(localized: "UDID"))
                }

                if let error = viewModel.uiState.createErrorMessage {
                    Section {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }

                buildUDIDTutorialSection()
            }
            .navigationTitle(String(localized: "Register Device"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(String(localized: "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if viewModel.uiState.isCreating {
                        ProgressView()
                    } else {
                        Button(String(localized: "Register")) {
                            Task {
                                let ok = await viewModel.create(
                                    name: name.trimmingCharacters(in: .whitespaces),
                                    platformRaw: platformRaw,
                                    udid: udid.trimmingCharacters(in: .whitespaces)
                                )
                                if ok { dismiss() }
                            }
                        }
                        .disabled(!canSubmit)
                    }
                }
            }
        }
    }
}
