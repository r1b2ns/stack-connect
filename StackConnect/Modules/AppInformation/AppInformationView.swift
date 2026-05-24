import SwiftUI
import UIKit

// MARK: - Factory

@MainActor
struct AppInformationViewFactory {
    static func build(app: AppModel, account: AccountModel) -> some View {
        AppInformationEntry(app: app, account: account)
    }
}

// MARK: - Entry

private struct AppInformationEntry: View {
    let app: AppModel
    let account: AccountModel

    @StateObject private var viewModel: AppInformationViewModel

    init(app: AppModel, account: AccountModel) {
        self.app = app
        self.account = account
        _viewModel = StateObject(wrappedValue: AppInformationViewModel(app: app, account: account))
    }

    var body: some View {
        AppInformationView(viewModel: viewModel)
    }
}

// MARK: - View

struct AppInformationView<ViewModel: AppInformationViewModelProtocol>: View {

    @ObservedObject var viewModel: ViewModel
    @EnvironmentObject private var homeCoordinator: HomeCoordinator

    private var canEditApps: Bool { viewModel.uiState.account.canEdit(.apps) }

    var body: some View {
        Group {
            if viewModel.uiState.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                buildForm()
            }
        }
        .navigationTitle(String(localized: "App Information"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
        .sheet(isPresented: $viewModel.uiState.showContentRightsSheet) {
            ContentRightsSheet(viewModel: viewModel)
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
        .overlay(alignment: .bottom) {
            if viewModel.uiState.isSyncing {
                buildSyncingIndicator()
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.3), value: viewModel.uiState.isSyncing)
        .toast(message: $viewModel.uiState.toastMessage)
    }

    // MARK: - Form

    private func buildForm() -> some View {
        List {
            buildLocalizationsSection()
            buildGeneralSection()
            buildAgeRatingSection()
            buildLinksSection()
        }
        .foregroundStyle(.primary)
    }

    // MARK: - Localizations Section

    private func buildLocalizationsSection() -> some View {
        Section {
            if let localizations = viewModel.uiState.appInfo?.localizations, !localizations.isEmpty {
                ForEach(localizations) { loc in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(loc.name ?? "–")
                                    .font(.body)
                                    .foregroundStyle(.primary)
                                if loc.locale == viewModel.uiState.appInfo?.primaryLocale {
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
                            if let subtitle = loc.subtitle {
                                Text(subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Text(localeName(loc.locale))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 2)
                }
            } else {
                Text(String(localized: "No localizations"))
                    .foregroundStyle(.secondary)
            }

            Button {
                if let appInfo = viewModel.uiState.appInfo {
                    homeCoordinator.navigateToManageLocalizations(
                        appInfoId: appInfo.id,
                        primaryLocale: appInfo.primaryLocale ?? "en-US",
                        account: viewModel.uiState.account
                    )
                }
            } label: {
                buildMenuRow(icon: "globe", color: .blue, title: String(localized: "Manage Localizations"))
            }
            .disabled(!canEditApps)
        } header: {
            Text("App Name & Localizations")
        }
    }

    // MARK: - General Section

    private func buildGeneralSection() -> some View {
        Section {
            if let bundleId = viewModel.uiState.app.bundleId as String? {
                buildCopyableInfoRow(label: String(localized: "Bundle ID"), value: bundleId)
            }

            if let sku = viewModel.uiState.appInfo?.sku {
                buildCopyableInfoRow(label: String(localized: "SKU"), value: sku)
            }

            buildCopyableInfoRow(label: String(localized: "Apple ID"), value: viewModel.uiState.app.id)

            Button {
                if let appInfo = viewModel.uiState.appInfo {
                    homeCoordinator.navigateToAppCategoryPicker(
                        appInfoId: appInfo.id,
                        primaryCategoryId: appInfo.primaryCategoryId,
                        primarySubcategoryId: appInfo.primarySubcategoryOneId,
                        secondaryCategoryId: appInfo.secondaryCategoryId,
                        secondarySubcategoryId: appInfo.secondarySubcategoryOneId,
                        account: viewModel.uiState.account
                    )
                }
            } label: {
                HStack {
                    buildMenuRow(icon: "square.grid.2x2.fill", color: .purple, title: String(localized: "Category"))
                    if let category = viewModel.uiState.appInfo?.primaryCategoryName {
                        Spacer()
                        Text(category)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .disabled(!canEditApps)

            Button {
                viewModel.uiState.showContentRightsSheet = true
            } label: {
                HStack {
                    buildMenuRow(icon: "doc.text.fill", color: .orange, title: String(localized: "Content Rights"))
                    if let declaration = viewModel.uiState.appInfo?.contentRightsDeclaration {
                        Spacer()
                        Text(contentRightsDisplayName(declaration))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .disabled(!canEditApps)
        } header: {
            Text("General Information")
        }
    }

    // MARK: - Age Rating Section

    private func buildAgeRatingSection() -> some View {
        Section {
            Button {
                if let ageRating = viewModel.uiState.ageRating {
                    homeCoordinator.navigateToAgeRating(
                        ageRating: ageRating,
                        account: viewModel.uiState.account
                    )
                }
            } label: {
                HStack {
                    buildMenuRow(icon: "shield.lefthalf.filled", color: .red, title: String(localized: "Age Rating"))
                    if let rating = viewModel.uiState.appInfo?.appStoreAgeRating {
                        Spacer()
                        Text(ageRatingDisplayName(rating))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .disabled(viewModel.uiState.ageRating == nil || !canEditApps)
        } header: {
            Text("Age Rating")
        }
    }

    // MARK: - Links Section

    private func buildLinksSection() -> some View {
        Section {
            if let url = URL(string: "https://apps.apple.com/app/id\(viewModel.uiState.app.id)") {
                Link(destination: url) {
                    buildMenuRow(icon: "safari.fill", color: .blue, title: String(localized: "View on App Store"))
                }
                .foregroundStyle(.primary)
            }
        }
    }

    // MARK: - Sync Indicator

    private func buildSyncingIndicator() -> some View {
        HStack(spacing: 8) {
            ProgressView()
                .scaleEffect(0.8)
            Text(String(localized: "Syncing..."))
                .font(.subheadline)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
    }

    // MARK: - Reusable Components

    private func buildCopyableInfoRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.trailing)
            Button {
                UIPasteboard.general.string = value
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .font(.subheadline)
    }

    private func buildMenuRow(icon: String, color: Color, title: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(color)
                .clipShape(RoundedRectangle(cornerRadius: 7))

            Text(title)
                .font(.body)
                .foregroundStyle(.primary)

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private func localeName(_ code: String) -> String {
        Locale.current.localizedString(forIdentifier: code) ?? code
    }

    private func ageRatingDisplayName(_ raw: String) -> String {
        switch raw {
        case "FOUR_PLUS":      return "4+"
        case "NINE_PLUS":      return "9+"
        case "TWELVE_PLUS":    return "12+"
        case "SEVENTEEN_PLUS": return "17+"
        default:               return raw
        }
    }

    private func contentRightsDisplayName(_ value: String) -> String {
        switch value {
        case "DOES_NOT_USE_THIRD_PARTY_CONTENT": return String(localized: "No third-party content")
        case "USES_THIRD_PARTY_CONTENT":         return String(localized: "Uses third-party content")
        default: return value
        }
    }
}

// MARK: - Content Rights Sheet

struct ContentRightsSheet<ViewModel: AppInformationViewModelProtocol>: View {

    @ObservedObject var viewModel: ViewModel
    @Environment(\.dismiss) private var dismiss

    private let options: [(String, String, String)] = [
        ("DOES_NOT_USE_THIRD_PARTY_CONTENT",
         String(localized: "This app does not use third-party content"),
         "checkmark.seal.fill"),
        ("USES_THIRD_PARTY_CONTENT",
         String(localized: "This app uses third-party content"),
         "doc.on.doc.fill"),
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(options, id: \.0) { value, label, icon in
                        let isSelected = viewModel.uiState.appInfo?.contentRightsDeclaration == value
                        Button {
                            Task { await viewModel.updateContentRights(value) }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                                    .frame(width: 24)

                                Text(label)
                                    .font(.body)
                                    .fontWeight(isSelected ? .semibold : .regular)
                                    .foregroundStyle(isSelected ? Color.accentColor : .primary)

                                Spacer()
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                } footer: {
                    Text("Indicate whether your app contains, shows, or accesses third-party content.")
                }
            }
            .navigationTitle(String(localized: "Content Rights"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) {
                        dismiss()
                        viewModel.uiState.showContentRightsSheet = false
                    }
                }
            }
        }
    }
}
