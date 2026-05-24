import SwiftUI

// MARK: - Available Locales

private let appStoreLocales: [String] = [
    "ar-SA", "ca", "cs", "da", "de-DE", "el", "en-AU", "en-CA", "en-GB", "en-US",
    "es-ES", "es-MX", "fi", "fr-CA", "fr-FR", "he", "hi", "hr", "hu", "id",
    "it", "ja", "ko", "ms", "nl-NL", "no", "pl", "pt-BR", "pt-PT", "ro",
    "ru", "sk", "sv", "th", "tr", "uk", "vi", "zh-Hans", "zh-Hant"
]

// MARK: - Factory

@MainActor
struct ManageLocalizationsViewFactory {
    static func build(appInfoId: String, primaryLocale: String, account: AccountModel) -> some View {
        ManageLocalizationsEntry(appInfoId: appInfoId, primaryLocale: primaryLocale, account: account)
    }
}

// MARK: - Entry

private struct ManageLocalizationsEntry: View {
    let appInfoId: String
    let primaryLocale: String
    let account: AccountModel

    @StateObject private var viewModel: ManageLocalizationsViewModel

    init(appInfoId: String, primaryLocale: String, account: AccountModel) {
        self.appInfoId = appInfoId
        self.primaryLocale = primaryLocale
        self.account = account
        _viewModel = StateObject(
            wrappedValue: ManageLocalizationsViewModel(
                appInfoId: appInfoId,
                primaryLocale: primaryLocale,
                account: account
            )
        )
    }

    var body: some View {
        ManageLocalizationsView(viewModel: viewModel)
    }
}

// MARK: - View

struct ManageLocalizationsView<ViewModel: ManageLocalizationsViewModelProtocol>: View {

    @ObservedObject var viewModel: ViewModel

    var body: some View {
        Group {
            if viewModel.uiState.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                buildList()
            }
        }
        .navigationTitle(String(localized: "Localizations"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { buildToolbar() }
        .task { await viewModel.load() }
        .sheet(isPresented: $viewModel.uiState.showEditSheet) {
            if let loc = viewModel.uiState.editingLocalization {
                EditLocalizationSheet(viewModel: viewModel, localization: loc)
            }
        }
        .sheet(isPresented: $viewModel.uiState.showAddSheet) {
            AddLocalizationSheet(viewModel: viewModel)
        }
        .alert(
            String(localized: "Error"),
            isPresented: Binding(
                get: { viewModel.uiState.error != nil },
                set: { if !$0 { viewModel.uiState.error = nil } }
            )
        ) {
            Button(String(localized: "OK"), role: .cancel) {
                viewModel.uiState.error = nil
            }
        } message: {
            if let error = viewModel.uiState.error {
                Text(error)
            }
        }
        .toast(message: $viewModel.uiState.toastMessage)
    }

    // MARK: - List

    private func buildList() -> some View {
        List {
            ForEach(viewModel.uiState.localizations) { loc in
                buildLocalizationRow(loc)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        if loc.locale != viewModel.uiState.primaryLocale {
                            Button(role: .destructive) {
                                Task { await viewModel.delete(localization: loc) }
                            } label: {
                                Label(String(localized: "Remove"), systemImage: "trash")
                            }
                        }
                    }
            }
        }
    }

    private func buildLocalizationRow(_ loc: AppInfoLocalizationModel) -> some View {
        Button {
            viewModel.uiState.editingLocalization = loc
            viewModel.uiState.showEditSheet = true
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(localeName(loc.locale))
                            .font(.body)
                            .foregroundStyle(.primary)

                        if loc.locale == viewModel.uiState.primaryLocale {
                            Text("Primary")
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.blue.opacity(0.15))
                                .foregroundStyle(.blue)
                                .clipShape(Capsule())
                        }
                    }

                    if let name = loc.name {
                        Text(name)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    if let subtitle = loc.subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 2)
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private func buildToolbar() -> some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                viewModel.uiState.showAddSheet = true
            } label: {
                Image(systemName: "plus")
            }
        }
    }

    // MARK: - Helpers

    private func localeName(_ code: String) -> String {
        Locale.current.localizedString(forIdentifier: code) ?? code
    }
}

// MARK: - Edit Localization Sheet

struct EditLocalizationSheet<ViewModel: ManageLocalizationsViewModelProtocol>: View {

    @ObservedObject var viewModel: ViewModel
    let localization: AppInfoLocalizationModel

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var subtitle: String

    init(viewModel: ViewModel, localization: AppInfoLocalizationModel) {
        self.viewModel = viewModel
        self.localization = localization
        _name = State(initialValue: localization.name ?? "")
        _subtitle = State(initialValue: localization.subtitle ?? "")
    }

    private var localeName: String {
        Locale.current.localizedString(forIdentifier: localization.locale) ?? localization.locale
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    buildInfoRow(label: String(localized: "Locale"), value: localeName)
                    buildInfoRow(label: String(localized: "Language Code"), value: localization.locale)
                } header: {
                    Text("Locale")
                }

                Section {
                    TextField(String(localized: "App Name"), text: $name)

                    VStack(alignment: .trailing, spacing: 2) {
                        TextField(String(localized: "Subtitle (optional)"), text: $subtitle)
                            .onChange(of: subtitle) { _, newValue in
                                if newValue.count > 30 {
                                    subtitle = String(newValue.prefix(30))
                                }
                            }

                        Text("\(30 - subtitle.count)")
                            .font(.caption2)
                            .foregroundStyle(subtitle.count >= 30 ? .red : .secondary)
                            .monospacedDigit()
                    }
                } header: {
                    Text("App Name & Subtitle")
                } footer: {
                    Text("The app name and subtitle visible on the App Store for this locale.")
                }
            }
            .navigationTitle(localeName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) {
                        dismiss()
                        viewModel.uiState.showEditSheet = false
                        viewModel.uiState.editingLocalization = nil
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if viewModel.uiState.isSaving {
                        ProgressView()
                    } else {
                        Button(String(localized: "Save")) {
                            var updated = localization
                            updated.name = name
                            updated.subtitle = subtitle.isEmpty ? nil : subtitle
                            Task { await viewModel.update(localization: updated) }
                        }
                        .disabled(name.isEmpty)
                    }
                }
            }
            .disabled(viewModel.uiState.isSaving)
        }
    }

    private func buildInfoRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .foregroundStyle(.primary)
        }
        .font(.subheadline)
    }
}

// MARK: - Add Localization Sheet

struct AddLocalizationSheet<ViewModel: ManageLocalizationsViewModelProtocol>: View {

    @ObservedObject var viewModel: ViewModel

    @Environment(\.dismiss) private var dismiss

    private var availableLocales: [String] {
        let existing = Set(viewModel.uiState.localizations.map(\.locale))
        return appStoreLocales.filter { !existing.contains($0) }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker(String(localized: "Locale"), selection: $viewModel.uiState.newLocale) {
                        Text(String(localized: "Select...")).tag("")
                        ForEach(availableLocales, id: \.self) { locale in
                            Text(Locale.current.localizedString(forIdentifier: locale) ?? locale)
                                .tag(locale)
                        }
                    }
                } header: {
                    Text("Locale")
                }

                Section {
                    TextField(String(localized: "App Name"), text: $viewModel.uiState.newName)
                    TextField(String(localized: "Subtitle (optional)"), text: $viewModel.uiState.newSubtitle)
                } header: {
                    Text("App Name & Subtitle")
                } footer: {
                    Text("App name is required. Subtitle is optional.")
                }

                if let error = viewModel.uiState.error {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .font(.subheadline)
                    }
                }
            }
            .navigationTitle(String(localized: "Add Localization"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) {
                        dismiss()
                        viewModel.uiState.showAddSheet = false
                        viewModel.uiState.error = nil
                        viewModel.uiState.newLocale = ""
                        viewModel.uiState.newName = ""
                        viewModel.uiState.newSubtitle = ""
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if viewModel.uiState.isSaving {
                        ProgressView()
                    } else {
                        Button(String(localized: "Add")) {
                            Task {
                                await viewModel.addLocalization(
                                    locale: viewModel.uiState.newLocale,
                                    name: viewModel.uiState.newName,
                                    subtitle: viewModel.uiState.newSubtitle.isEmpty
                                        ? nil : viewModel.uiState.newSubtitle
                                )
                            }
                        }
                        .disabled(
                            viewModel.uiState.newLocale.isEmpty ||
                            viewModel.uiState.newName.isEmpty
                        )
                    }
                }
            }
            .disabled(viewModel.uiState.isSaving)
        }
    }
}
