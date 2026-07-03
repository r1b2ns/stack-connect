import SwiftUI

// MARK: - Factory

@MainActor
struct ScreenshotGridViewFactory {
    static func build(screenshots: [ScreenshotModel], account: AccountModel, appStoreState: AppStoreState?) -> some View {
        ScreenshotGridView(screenshots: screenshots, account: account, appStoreState: appStoreState)
    }
}

// MARK: - ViewModel

@MainActor
final class ScreenshotGridViewModel: ObservableObject {

    @Published var screenshots: [ScreenshotModel]
    @Published var isSelectionMode = false
    @Published var selectedIds: Set<String> = []
    @Published var showDeleteConfirmation = false
    @Published var isDeleting = false
    @Published var deleteError: String?

    private let account: AccountModel
    private let appStoreState: AppStoreState?
    private let keychain: KeyStorable

    init(
        screenshots: [ScreenshotModel],
        account: AccountModel,
        appStoreState: AppStoreState?,
        keychain: KeyStorable = KeychainStorable.shared
    ) {
        self.screenshots = screenshots
        self.account = account
        self.appStoreState = appStoreState
        self.keychain = keychain
    }

    /// Selection (and thus deletion) is only offered while the version is still
    /// editable (Prepare for Submission).
    var canSelect: Bool {
        appStoreState == .prepareForSubmission
    }

    var selectedCount: Int { selectedIds.count }

    func enterSelectionMode() {
        isSelectionMode = true
    }

    func cancelSelection() {
        isSelectionMode = false
        selectedIds.removeAll()
    }

    func toggleSelection(_ screenshot: ScreenshotModel) {
        if selectedIds.contains(screenshot.id) {
            selectedIds.remove(screenshot.id)
        } else {
            selectedIds.insert(screenshot.id)
        }
    }

    func isSelected(_ screenshot: ScreenshotModel) -> Bool {
        selectedIds.contains(screenshot.id)
    }

    /// Deletes every selected screenshot via the core, removing each from the
    /// grid as it succeeds. Stops at the first failure and surfaces the error.
    func deleteSelected() async {
        let ids = selectedIds
        guard !ids.isEmpty else { return }
        guard let credentials: AppleCredentials = keychain.object(forKey: "credentials.\(account.id)") else {
            return
        }

        deleteError = nil
        isDeleting = true
        defer { isDeleting = false }

        let connection = AppleAccountConnection(credentials: credentials)
        do {
            for id in ids {
                try await connection.deleteScreenshot(screenshotId: id)
                screenshots.removeAll { $0.id == id }
                selectedIds.remove(id)
            }
            Log.print.info("[Screenshots] Deleted \(ids.count) selected screenshots")
            cancelSelection()
        } catch {
            deleteError = error.localizedDescription
            Log.print.error("[Screenshots] Delete selected failed: \(error.localizedDescription)")
        }
    }
}

// MARK: - View

struct ScreenshotGridView: View {

    @StateObject private var viewModel: ScreenshotGridViewModel
    @EnvironmentObject private var homeCoordinator: HomeCoordinator

    private let account: AccountModel
    private let appStoreState: AppStoreState?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 3)

    init(screenshots: [ScreenshotModel], account: AccountModel, appStoreState: AppStoreState?) {
        self.account = account
        self.appStoreState = appStoreState
        _viewModel = StateObject(wrappedValue: ScreenshotGridViewModel(
            screenshots: screenshots,
            account: account,
            appStoreState: appStoreState
        ))
    }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(Array(viewModel.screenshots.enumerated()), id: \.element.id) { index, screenshot in
                    buildCell(screenshot, index: index)
                }
            }
            .padding(2)
        }
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if viewModel.canSelect && !viewModel.screenshots.isEmpty {
                    if viewModel.isSelectionMode {
                        Button(String(localized: "Cancel")) {
                            viewModel.cancelSelection()
                        }
                    } else {
                        Button(String(localized: "Select")) {
                            viewModel.enterSelectionMode()
                        }
                    }
                }
            }
            ToolbarItemGroup(placement: .bottomBar) {
                if viewModel.isSelectionMode && viewModel.selectedCount > 0 {
                    Spacer()
                    Button(role: .destructive) {
                        viewModel.showDeleteConfirmation = true
                    } label: {
                        Image(systemName: "trash")
                    }
                    .disabled(viewModel.isDeleting)
                    .accessibilityLabel(String(localized: "Delete Selected Screenshots"))
                }
            }
        }
        .alert(
            String(localized: "Delete Screenshots"),
            isPresented: $viewModel.showDeleteConfirmation
        ) {
            Button(String(localized: "Cancel"), role: .cancel) {}
            Button(String(localized: "Delete"), role: .destructive) {
                Task { await viewModel.deleteSelected() }
            }
        } message: {
            Text(String(localized: "This permanently removes the \(viewModel.selectedCount) selected screenshot(s). This action cannot be undone."))
        }
        .alert(
            String(localized: "Delete Failed"),
            isPresented: Binding(
                get: { viewModel.deleteError != nil },
                set: { if !$0 { viewModel.deleteError = nil } }
            )
        ) {
            Button(String(localized: "OK"), role: .cancel) { viewModel.deleteError = nil }
        } message: {
            Text(viewModel.deleteError ?? "")
        }
    }

    private var navigationTitle: String {
        if viewModel.isSelectionMode && viewModel.selectedCount > 0 {
            return String(localized: "\(viewModel.selectedCount) Selected")
        }
        return String(localized: "Screenshots")
    }

    private func buildCell(_ screenshot: ScreenshotModel, index: Int) -> some View {
        Button {
            if viewModel.isSelectionMode {
                viewModel.toggleSelection(screenshot)
            } else {
                homeCoordinator.navigateToScreenshotPage(
                    screenshots: viewModel.screenshots,
                    startIndex: index,
                    account: account,
                    appStoreState: appStoreState
                )
            }
        } label: {
            buildThumbnail(screenshot)
        }
        .buttonStyle(.plain)
    }

    private func buildThumbnail(_ screenshot: ScreenshotModel) -> some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let urlStr = screenshot.imageUrl, let url = URL(string: urlStr) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                        case .failure:
                            thumbnailPlaceholder
                        case .empty:
                            ProgressView()
                        @unknown default:
                            thumbnailPlaceholder
                        }
                    }
                } else {
                    thumbnailPlaceholder
                }
            }
            .clipped()
            .overlay {
                if viewModel.isSelectionMode && viewModel.isSelected(screenshot) {
                    Color.accentColor.opacity(0.25)
                }
            }
            .overlay(alignment: .topTrailing) {
                if viewModel.isSelectionMode {
                    Image(systemName: viewModel.isSelected(screenshot) ? "checkmark.circle.fill" : "circle")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(
                            .white,
                            viewModel.isSelected(screenshot) ? Color.accentColor : Color.black.opacity(0.35)
                        )
                        .font(.title3)
                        .padding(4)
                }
            }
    }

    private var thumbnailPlaceholder: some View {
        Rectangle()
            .fill(Color.gray.opacity(0.15))
            .overlay {
                Image(systemName: "photo")
                    .foregroundStyle(.secondary)
            }
    }
}
