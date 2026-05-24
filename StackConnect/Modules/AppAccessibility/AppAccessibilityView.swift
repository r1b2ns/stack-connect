import SwiftUI

// MARK: - Factory

@MainActor
struct AppAccessibilityViewFactory {
    static func build(appId: String, account: AccountModel) -> some View {
        AppAccessibilityEntryView(appId: appId, account: account)
    }
}

// MARK: - Entry

private struct AppAccessibilityEntryView: View {
    let appId: String
    let account: AccountModel

    @StateObject private var viewModel: AppAccessibilityViewModel

    init(appId: String, account: AccountModel) {
        self.appId = appId
        self.account = account
        _viewModel = StateObject(wrappedValue: AppAccessibilityViewModel(appId: appId, account: account))
    }

    var body: some View {
        AppAccessibilityView(viewModel: viewModel)
    }
}

// MARK: - View

struct AppAccessibilityView<ViewModel: AppAccessibilityViewModelProtocol>: View {

    @ObservedObject var viewModel: ViewModel

    var body: some View {
        buildContent()
            .navigationTitle(String(localized: "App Accessibility"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { buildToolbar() }
            .task { await viewModel.load() }
            .refreshable { await viewModel.load() }
            .sheet(item: $viewModel.uiState.editingDeclaration) { declaration in
                EditAccessibilitySheet(
                    declaration: declaration,
                    isSaving: viewModel.uiState.isSaving
                ) { updated in
                    Task { await viewModel.save(declaration: updated) }
                } onPublish: { updated in
                    Task { await viewModel.publish(declaration: updated) }
                } onCancel: {
                    viewModel.uiState.editingDeclaration = nil
                }
            }
            .sheet(isPresented: $viewModel.uiState.showAddDevice) {
                AddDeviceFamilySheet(
                    available: viewModel.uiState.availableDeviceFamilies,
                    isSaving: viewModel.uiState.isSaving
                ) { deviceFamily in
                    Task { await viewModel.create(deviceFamily: deviceFamily) }
                } onCancel: {
                    viewModel.uiState.showAddDevice = false
                }
            }
            .alert(
                String(localized: "Delete Declaration"),
                isPresented: Binding(
                    get: { viewModel.uiState.confirmDelete != nil },
                    set: { if !$0 { viewModel.uiState.confirmDelete = nil } }
                )
            ) {
                Button(String(localized: "Delete"), role: .destructive) {
                    if let decl = viewModel.uiState.confirmDelete {
                        Task { await viewModel.delete(declaration: decl) }
                    }
                }
                Button(String(localized: "Cancel"), role: .cancel) {
                    viewModel.uiState.confirmDelete = nil
                }
            } message: {
                if let decl = viewModel.uiState.confirmDelete {
                    Text("Are you sure you want to delete the accessibility declaration for \(decl.deviceFamilyDisplayName)?")
                }
            }
            .toast(message: $viewModel.uiState.toastMessage)
    }

    // MARK: - Content

    @ViewBuilder
    private func buildContent() -> some View {
        if viewModel.uiState.isLoading && viewModel.uiState.declarations.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.uiState.activeDeclarations.isEmpty {
            buildEmptyState()
        } else {
            buildList()
        }
    }

    @ViewBuilder
    private func buildEmptyState() -> some View {
        if let error = viewModel.uiState.error {
            ContentUnavailableView {
                Label(String(localized: "Error"), systemImage: "exclamationmark.triangle")
            } description: {
                Text(error)
            }
        } else {
            ContentUnavailableView {
                Label(String(localized: "No Declarations"), systemImage: "accessibility")
            } description: {
                Text("No accessibility declarations found. Tap + to add one.")
            }
        }
    }

    private func buildList() -> some View {
        List {
            ForEach(viewModel.uiState.activeDeclarations) { declaration in
                buildDeclarationSection(declaration)
            }
        }
    }

    // MARK: - Declaration Section

    private func buildDeclarationSection(_ declaration: AccessibilityDeclarationModel) -> some View {
        Section {
            Button {
                viewModel.uiState.editingDeclaration = declaration
            } label: {
                buildDeclarationRow(declaration)
            }
            .foregroundStyle(.primary)
            .disabled(!viewModel.uiState.account.canEdit(.apps))
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                if declaration.state == "DRAFT" && viewModel.uiState.account.canDelete(.apps) {
                    Button(role: .destructive) {
                        viewModel.uiState.confirmDelete = declaration
                    } label: {
                        Label(String(localized: "Delete"), systemImage: "trash")
                    }
                }
            }
        } header: {
            HStack(spacing: 6) {
                Image(systemName: declaration.deviceFamilyIcon)
                Text(declaration.deviceFamilyDisplayName)
            }
        }
    }

    private func buildDeclarationRow(_ declaration: AccessibilityDeclarationModel) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // Status badge
            HStack {
                Text(declaration.stateDisplayName)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(stateColor(declaration.stateColor))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(stateColor(declaration.stateColor).opacity(0.12))
                    .clipShape(Capsule())

                Spacer()

                Text("\(declaration.supportedFeaturesCount)/9")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            // Feature grid
            buildFeatureGrid(declaration)
        }
        .padding(.vertical, 4)
    }

    private func buildFeatureGrid(_ d: AccessibilityDeclarationModel) -> some View {
        let features: [(String, String, Bool)] = [
            ("VoiceOver", "eye", d.supportsVoiceover),
            ("Voice Control", "mic.fill", d.supportsVoiceControl),
            ("Captions", "captions.bubble.fill", d.supportsCaptions),
            ("Audio Desc.", "speaker.wave.3.fill", d.supportsAudioDescriptions),
            ("Dark Mode", "moon.fill", d.supportsDarkInterface),
            ("Larger Text", "textformat.size.larger", d.supportsLargerText),
            ("Contrast", "circle.lefthalf.filled", d.supportsSufficientContrast),
            ("Reduce Motion", "figure.walk", d.supportsReducedMotion),
            ("No Color Alone", "paintpalette.fill", d.supportsDifferentiateWithoutColor),
        ]

        return LazyVGrid(columns: [
            GridItem(.flexible(), spacing: 8),
            GridItem(.flexible(), spacing: 8),
            GridItem(.flexible(), spacing: 8)
        ], spacing: 6) {
            ForEach(features, id: \.0) { name, icon, supported in
                HStack(spacing: 4) {
                    Image(systemName: supported ? "checkmark.circle.fill" : "circle")
                        .font(.caption2)
                        .foregroundStyle(supported ? Color.green : Color.gray.opacity(0.4))
                    Text(name)
                        .font(.caption2)
                        .foregroundStyle(supported ? Color.primary : Color.gray.opacity(0.4))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private func buildToolbar() -> some ToolbarContent {
        if viewModel.uiState.account.canAdd(.apps) {
            ToolbarItem(placement: .primaryAction) {
                if !viewModel.uiState.availableDeviceFamilies.isEmpty {
                    Button {
                        viewModel.uiState.showAddDevice = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func stateColor(_ color: AppStoreStateColor) -> Color {
        switch color {
        case .green:  return .green
        case .orange: return .orange
        case .red:    return .red
        case .gray:   return .gray
        case .blue:   return .blue
        case .yellow: return .yellow
        }
    }
}

// MARK: - Edit Accessibility Sheet

struct EditAccessibilitySheet: View {

    @Environment(\.dismiss) private var dismiss
    @State var declaration: AccessibilityDeclarationModel
    let isSaving: Bool
    let onSave: (AccessibilityDeclarationModel) -> Void
    let onPublish: (AccessibilityDeclarationModel) -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    buildToggle(
                        String(localized: "VoiceOver"),
                        icon: "eye",
                        description: String(localized: "Screen reader support for blind and low-vision users"),
                        isOn: $declaration.supportsVoiceover
                    )
                    buildToggle(
                        String(localized: "Voice Control"),
                        icon: "mic.fill",
                        description: String(localized: "Navigate and interact using voice commands"),
                        isOn: $declaration.supportsVoiceControl
                    )
                } header: {
                    Text("Input")
                }

                Section {
                    buildToggle(
                        String(localized: "Captions"),
                        icon: "captions.bubble.fill",
                        description: String(localized: "Subtitles and closed captions for audio content"),
                        isOn: $declaration.supportsCaptions
                    )
                    buildToggle(
                        String(localized: "Audio Descriptions"),
                        icon: "speaker.wave.3.fill",
                        description: String(localized: "Narrated descriptions of visual elements in video"),
                        isOn: $declaration.supportsAudioDescriptions
                    )
                } header: {
                    Text("Media")
                }

                Section {
                    buildToggle(
                        String(localized: "Dark Mode"),
                        icon: "moon.fill",
                        description: String(localized: "Supports dark interface appearance"),
                        isOn: $declaration.supportsDarkInterface
                    )
                    buildToggle(
                        String(localized: "Larger Text"),
                        icon: "textformat.size.larger",
                        description: String(localized: "Adapts to Dynamic Type font sizes"),
                        isOn: $declaration.supportsLargerText
                    )
                    buildToggle(
                        String(localized: "Sufficient Contrast"),
                        icon: "circle.lefthalf.filled",
                        description: String(localized: "Meets minimum contrast ratio requirements"),
                        isOn: $declaration.supportsSufficientContrast
                    )
                    buildToggle(
                        String(localized: "Reduce Motion"),
                        icon: "figure.walk",
                        description: String(localized: "Respects the Reduce Motion accessibility preference"),
                        isOn: $declaration.supportsReducedMotion
                    )
                    buildToggle(
                        String(localized: "Differentiate Without Color"),
                        icon: "paintpalette.fill",
                        description: String(localized: "Information is conveyed without relying on color alone"),
                        isOn: $declaration.supportsDifferentiateWithoutColor
                    )
                } header: {
                    Text("Visual")
                }

                if declaration.state == "DRAFT" {
                    Section {
                        Button {
                            onPublish(declaration)
                        } label: {
                            HStack {
                                Spacer()
                                Label(String(localized: "Save & Publish"), systemImage: "arrow.up.circle.fill")
                                    .fontWeight(.medium)
                                Spacer()
                            }
                        }
                        .foregroundStyle(.green)
                    } footer: {
                        Text("Publishing will make this declaration visible on the App Store.")
                    }
                }
            }
            .navigationTitle(declaration.deviceFamilyDisplayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) {
                        dismiss()
                        onCancel()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button(String(localized: "Save")) {
                            onSave(declaration)
                        }
                    }
                }
            }
            .disabled(isSaving)
        }
    }

    private func buildToggle(_ title: String, icon: String, description: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Label(title, systemImage: icon)
                    .font(.body)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Add Device Family Sheet

struct AddDeviceFamilySheet: View {

    @Environment(\.dismiss) private var dismiss
    let available: [String]
    let isSaving: Bool
    let onCreate: (String) -> Void
    let onCancel: () -> Void

    private func displayName(for family: String) -> String {
        switch family {
        case "IPHONE":      return "iPhone"
        case "IPAD":        return "iPad"
        case "APPLE_TV":    return "Apple TV"
        case "APPLE_WATCH": return "Apple Watch"
        case "MAC":         return "Mac"
        case "VISION":      return "Apple Vision Pro"
        default:            return family
        }
    }

    private func icon(for family: String) -> String {
        switch family {
        case "IPHONE":      return "iphone"
        case "IPAD":        return "ipad"
        case "APPLE_TV":    return "appletv"
        case "APPLE_WATCH": return "applewatch"
        case "MAC":         return "macbook"
        case "VISION":      return "visionpro"
        default:            return "rectangle"
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(available, id: \.self) { family in
                        Button {
                            onCreate(family)
                        } label: {
                            Label(displayName(for: family), systemImage: icon(for: family))
                                .font(.body)
                        }
                        .disabled(isSaving)
                    }
                } header: {
                    Text("Select Device Family")
                } footer: {
                    Text("A new accessibility declaration will be created as a draft for the selected device.")
                }
            }
            .navigationTitle(String(localized: "Add Device"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) {
                        dismiss()
                        onCancel()
                    }
                }
            }
        }
    }
}
