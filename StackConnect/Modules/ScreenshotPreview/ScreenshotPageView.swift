import SwiftUI

// MARK: - Factory

@MainActor
struct ScreenshotPageViewFactory {
    static func build(screenshots: [ScreenshotModel], startIndex: Int = 0, account: AccountModel, appStoreState: AppStoreState?) -> some View {
        ScreenshotPageView(screenshots: screenshots, startIndex: startIndex, account: account, appStoreState: appStoreState)
    }
}

// MARK: - ViewModel

@MainActor
final class ScreenshotPageViewModel: ObservableObject {

    @Published var screenshots: [ScreenshotModel]
    @Published var pendingDelete: ScreenshotModel?
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

    /// Individual deletion is only offered while the version is still editable
    /// (Prepare for Submission).
    var canDelete: Bool {
        appStoreState == .prepareForSubmission
    }

    /// Deletes `screenshot` via the core, removing it from the pager on success.
    func deleteScreenshot(_ screenshot: ScreenshotModel) async {
        guard let index = screenshots.firstIndex(where: { $0.id == screenshot.id }) else { return }
        guard let credentials: AppleCredentials = keychain.object(forKey: "credentials.\(account.id)") else {
            return
        }

        deleteError = nil
        isDeleting = true
        defer { isDeleting = false }

        let connection = AppleAccountConnection(credentials: credentials)
        do {
            try await connection.deleteScreenshot(screenshotId: screenshot.id)
            Log.print.info("[Screenshots] Deleted screenshot \(screenshot.id)")
            screenshots.remove(at: index)
        } catch {
            deleteError = error.localizedDescription
            Log.print.error("[Screenshots] Delete screenshot failed: \(error.localizedDescription)")
        }
    }
}

// MARK: - View

struct ScreenshotPageView: View {

    @StateObject private var viewModel: ScreenshotPageViewModel
    @State private var currentIndex = 0
    @Environment(\.dismiss) private var dismiss

    init(screenshots: [ScreenshotModel], startIndex: Int = 0, account: AccountModel, appStoreState: AppStoreState?) {
        _currentIndex = State(initialValue: max(0, min(startIndex, max(screenshots.count - 1, 0))))
        _viewModel = StateObject(wrappedValue: ScreenshotPageViewModel(
            screenshots: screenshots,
            account: account,
            appStoreState: appStoreState
        ))
    }

    var body: some View {
        TabView(selection: $currentIndex) {
            ForEach(Array(viewModel.screenshots.enumerated()), id: \.element.id) { index, screenshot in
                buildScreenshotPage(screenshot)
                    .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .automatic))
        .navigationTitle("\(min(currentIndex + 1, max(viewModel.screenshots.count, 1))) / \(viewModel.screenshots.count)")
        .navigationBarTitleDisplayMode(.inline)
        .background(Color.black)
        .ignoresSafeArea(.container, edges: .bottom)
        .alert(
            String(localized: "Delete Screenshot"),
            isPresented: $viewModel.showDeleteConfirmation,
            presenting: viewModel.pendingDelete
        ) { screenshot in
            Button(String(localized: "Cancel"), role: .cancel) {
                viewModel.pendingDelete = nil
            }
            Button(String(localized: "Delete"), role: .destructive) {
                Task {
                    await viewModel.deleteScreenshot(screenshot)
                    viewModel.pendingDelete = nil
                    if viewModel.screenshots.isEmpty {
                        dismiss()
                    } else if currentIndex >= viewModel.screenshots.count {
                        currentIndex = viewModel.screenshots.count - 1
                    }
                }
            }
        } message: { _ in
            Text(String(localized: "This permanently removes this screenshot. This action cannot be undone."))
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

    private func buildScreenshotPage(_ screenshot: ScreenshotModel) -> some View {
        Group {
            if let urlStr = screenshot.imageUrl,
               let url = URL(string: urlStr) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                    case .failure:
                        buildPlaceholder()
                    case .empty:
                        ProgressView()
                            .tint(.white)
                    @unknown default:
                        buildPlaceholder()
                    }
                }
            } else {
                buildPlaceholder()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .bottom) {
            if viewModel.canDelete {
                Button(role: .destructive) {
                    viewModel.pendingDelete = screenshot
                    viewModel.showDeleteConfirmation = true
                } label: {
                    Image(systemName: "trash.circle.fill")
                        .font(.largeTitle)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .red)
                        .padding()
                }
                .disabled(viewModel.isDeleting)
                .accessibilityLabel(String(localized: "Delete Screenshot"))
                .padding(.bottom, 50)
            }
        }
    }

    private func buildPlaceholder() -> some View {
        VStack(spacing: 12) {
            Image(systemName: "photo")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("Image unavailable")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}
