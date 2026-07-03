import SwiftUI
import Foundation

// MARK: - Device Type

enum ScreenshotDeviceType: String, CaseIterable, Identifiable, Hashable {
    case iPhone
    case iPad
    case appleWatch
    case appleTV
    case mac
    case visionPro
    case iMessage

    var id: String { rawValue }

    var title: String {
        switch self {
        case .iPhone:     return "iPhone"
        case .iPad:       return "iPad"
        case .appleWatch: return "Apple Watch"
        case .appleTV:    return "Apple TV"
        case .mac:        return "Mac"
        case .visionPro:  return "Apple Vision Pro"
        case .iMessage:   return "iMessage App"
        }
    }

    var icon: String {
        switch self {
        case .iPhone:     return "iphone"
        case .iPad:       return "ipad"
        case .appleWatch: return "applewatch"
        case .appleTV:    return "appletv"
        case .mac:        return "macbook"
        case .visionPro:  return "visionpro"
        case .iMessage:   return "message.fill"
        }
    }

    var platform: AppPlatform {
        switch self {
        case .iPhone, .iPad, .iMessage: return .ios
        case .mac:                       return .macOs
        case .appleTV:                   return .tvOs
        case .visionPro:                 return .visionOs
        case .appleWatch:                return .ios
        }
    }
}

// MARK: - Factory

@MainActor
struct ScreenshotPreviewViewFactory {
    static func build(versionId: String, account: AccountModel, localizationId: String? = nil, platform: AppPlatform? = nil, appStoreState: AppStoreState? = nil) -> some View {
        ScreenshotPreviewEntry(versionId: versionId, account: account, localizationId: localizationId, platform: platform, appStoreState: appStoreState)
    }
}

// MARK: - Entry

private struct ScreenshotPreviewEntry: View {
    let versionId: String
    let account: AccountModel
    let localizationId: String?
    let platform: AppPlatform?
    let appStoreState: AppStoreState?

    @StateObject private var viewModel: ScreenshotPreviewViewModel

    init(versionId: String, account: AccountModel, localizationId: String?, platform: AppPlatform?, appStoreState: AppStoreState?) {
        self.versionId = versionId
        self.account = account
        self.localizationId = localizationId
        self.platform = platform
        self.appStoreState = appStoreState
        _viewModel = StateObject(wrappedValue: ScreenshotPreviewViewModel(
            versionId: versionId,
            account: account,
            localizationId: localizationId,
            platform: platform,
            appStoreState: appStoreState
        ))
    }

    var body: some View {
        ScreenshotPreviewContentView(viewModel: viewModel)
    }
}

// MARK: - ViewModel

@MainActor
final class ScreenshotPreviewViewModel: ObservableObject {

    @Published var screenshotSets: [ScreenshotSetModel] = []
    @Published var isLoading = false

    // Bulk download / zip state
    @Published var isPreparingDownload = false
    @Published var isZipping = false
    @Published var downloadedCount = 0
    @Published var totalCount = 0
    @Published var zipURL: URL?
    @Published var downloadError: String?

    // Delete-all state
    @Published var showDeleteAllConfirmation = false
    @Published var isDeleting = false
    @Published var deleteError: String?

    var hasScreenshots: Bool {
        screenshotSets.contains { !$0.screenshots.isEmpty }
    }

    /// The "Delete All" action is only offered while the version is still
    /// editable (Prepare for Submission) and there is something to delete.
    var canDeleteAll: Bool {
        appStoreState == .prepareForSubmission && hasScreenshots
    }

    /// Device types relevant to this version's platform. When the platform is
    /// unknown, fall back to showing every device type.
    var availableDeviceTypes: [ScreenshotDeviceType] {
        guard let platform else { return ScreenshotDeviceType.allCases }
        return ScreenshotDeviceType.allCases.filter { $0.platform == platform }
    }

    private let versionId: String
    let account: AccountModel
    private let localizationId: String?
    private let platform: AppPlatform?
    let appStoreState: AppStoreState?
    private let keychain: KeyStorable

    init(
        versionId: String,
        account: AccountModel,
        localizationId: String? = nil,
        platform: AppPlatform? = nil,
        appStoreState: AppStoreState? = nil,
        keychain: KeyStorable = KeychainStorable.shared
    ) {
        self.versionId = versionId
        self.account = account
        self.localizationId = localizationId
        self.platform = platform
        self.appStoreState = appStoreState
        self.keychain = keychain
    }

    func loadScreenshots() async {
        isLoading = true

        guard let credentials: AppleCredentials = keychain.object(forKey: "credentials.\(account.id)") else {
            isLoading = false
            return
        }

        let connection = AppleAccountConnection(credentials: credentials)

        do {
            let locId: String
            if let localizationId {
                locId = localizationId
            } else {
                let localizations = try await connection.fetchLocalizations(versionId: versionId)
                guard let first = localizations.first?.id else {
                    isLoading = false
                    return
                }
                locId = first
            }

            self.screenshotSets = try await connection.fetchScreenshotSets(localizationId: locId)
            Log.print.info("[Screenshots] Loaded \(self.screenshotSets.count) screenshot sets")
        } catch {
            Log.print.error("[Screenshots] Load failed: \(error.localizedDescription)")
        }

        isLoading = false
    }

    func sets(for device: ScreenshotDeviceType) -> [ScreenshotSetModel] {
        screenshotSets.filter { $0.deviceCategory == device && !$0.screenshots.isEmpty }
    }

    // MARK: - Bulk download + zip

    /// Downloads every screenshot (all devices in the current localization),
    /// organizing them into folders per size, then zips the result and exposes
    /// `zipURL` for sharing. Progress is published via `downloadedCount`/`totalCount`.
    func downloadAllScreenshots() async {
        let items: [(set: ScreenshotSetModel, shot: ScreenshotModel)] = screenshotSets.flatMap { set in
            set.screenshots.compactMap { shot in
                (shot.imageUrl?.isEmpty == false) ? (set, shot) : nil
            }
        }
        guard !items.isEmpty else { return }

        downloadError = nil
        zipURL = nil
        downloadedCount = 0
        totalCount = items.count
        isZipping = false
        isPreparingDownload = true
        defer {
            isPreparingDownload = false
            isZipping = false
        }

        let fileManager = FileManager.default
        let workDir = fileManager.temporaryDirectory
            .appendingPathComponent("Screenshots-\(versionId)", isDirectory: true)

        do {
            // Start from a clean working directory.
            try? fileManager.removeItem(at: workDir)
            try fileManager.createDirectory(at: workDir, withIntermediateDirectories: true)

            var perSetIndex: [String: Int] = [:]
            for item in items {
                defer { downloadedCount += 1 }
                guard let urlStr = item.shot.imageUrl, let url = URL(string: urlStr) else { continue }

                let (data, _) = try await URLSession.shared.data(from: url)

                let subdir = workDir.appendingPathComponent(sanitize(item.set.displayName), isDirectory: true)
                try? fileManager.createDirectory(at: subdir, withIntermediateDirectories: true)

                let index = (perSetIndex[item.set.id] ?? 0) + 1
                perSetIndex[item.set.id] = index
                let base = item.shot.fileName.map(sanitize) ?? "\(item.shot.id).png"
                let destination = subdir.appendingPathComponent("\(index)-\(base)")
                try await Task.detached { try data.write(to: destination, options: .atomic) }.value
            }

            isZipping = true
            let zip = try await Task.detached { try ScreenshotPreviewViewModel.zipDirectory(workDir) }.value
            zipURL = zip
            let count = totalCount
            Log.print.info("[Screenshots] Zipped \(count) screenshots → \(zip.lastPathComponent)")
        } catch {
            downloadError = error.localizedDescription
            Log.print.error("[Screenshots] Bulk download failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Delete all

    /// Deletes every screenshot set of the current localization, then reloads to
    /// reflect the server state. Only meaningful while the version is in Prepare
    /// for Submission (guarded by `canDeleteAll`).
    func deleteAllScreenshots() async {
        let sets = screenshotSets
        guard !sets.isEmpty else { return }

        guard let credentials: AppleCredentials = keychain.object(forKey: "credentials.\(account.id)") else {
            return
        }

        deleteError = nil
        isDeleting = true
        defer { isDeleting = false }

        let connection = AppleAccountConnection(credentials: credentials)
        do {
            for set in sets {
                try await connection.deleteScreenshotSet(screenshotSetId: set.id)
            }
            Log.print.info("[Screenshots] Deleted \(sets.count) screenshot sets")
            await loadScreenshots()
        } catch {
            deleteError = error.localizedDescription
            Log.print.error("[Screenshots] Delete all failed: \(error.localizedDescription)")
        }
    }

    private func sanitize(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        let cleaned = name.components(separatedBy: invalid).joined(separator: "-")
        return cleaned.isEmpty ? "screenshot" : cleaned
    }

    /// Zips a directory using NSFileCoordinator's `.forUploading` option, which
    /// produces a `.zip` of the folder without any third-party dependency.
    nonisolated static func zipDirectory(_ source: URL) throws -> URL {
        let coordinator = NSFileCoordinator()
        var coordinatorError: NSError?
        var copyError: Error?
        var resultURL: URL?

        coordinator.coordinate(readingItemAt: source, options: [.forUploading], error: &coordinatorError) { zippedURL in
            let destination = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(source.lastPathComponent).zip")
            do {
                try? FileManager.default.removeItem(at: destination)
                try FileManager.default.copyItem(at: zippedURL, to: destination)
                resultURL = destination
            } catch {
                copyError = error
            }
        }

        if let coordinatorError { throw coordinatorError }
        if let copyError { throw copyError }
        guard let resultURL else {
            throw NSError(
                domain: "Screenshots",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: String(localized: "Failed to create the zip file.")]
            )
        }
        return resultURL
    }
}

// MARK: - Content View

struct ScreenshotPreviewContentView: View {

    @ObservedObject var viewModel: ScreenshotPreviewViewModel
    @EnvironmentObject private var homeCoordinator: HomeCoordinator

    var body: some View {
        buildContent()
            .navigationTitle(String(localized: "Preview and Screenshots"))
            .navigationBarTitleDisplayMode(.inline)
            .task { await viewModel.loadScreenshots() }
            .safeAreaInset(edge: .bottom) {
                buildDownloadBar()
            }
            .alert(String(localized: "Delete All Screenshots"), isPresented: $viewModel.showDeleteAllConfirmation) {
                Button(String(localized: "Cancel"), role: .cancel) {}
                Button(String(localized: "Delete All"), role: .destructive) {
                    Task { await viewModel.deleteAllScreenshots() }
                }
            } message: {
                Text(String(localized: "This permanently removes every screenshot for this localization. This action cannot be undone."))
            }
    }

    // MARK: - Download / Share bar

    @ViewBuilder
    private func buildDownloadBar() -> some View {
        if !viewModel.isLoading && viewModel.hasScreenshots {
            VStack(spacing: 8) {
                if let zipURL = viewModel.zipURL {
                    ShareLink(item: zipURL) {
                        Label(String(localized: "Share Screenshots (.zip)"), systemImage: "square.and.arrow.up")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .foregroundStyle(.white)
                            .background(Color.accentColor)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    Button(String(localized: "Download Again")) {
                        Task { await viewModel.downloadAllScreenshots() }
                    }
                    .font(.caption)
                } else if viewModel.isPreparingDownload {
                    VStack(spacing: 6) {
                        ProgressView(
                            value: Double(viewModel.downloadedCount),
                            total: Double(max(viewModel.totalCount, 1))
                        )
                        Text(viewModel.isZipping
                             ? String(localized: "Creating zip…")
                             : String(localized: "Downloading \(viewModel.downloadedCount) of \(viewModel.totalCount)"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Button {
                        Task { await viewModel.downloadAllScreenshots() }
                    } label: {
                        Label(String(localized: "Download All Screenshots"), systemImage: "arrow.down.circle.fill")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .foregroundStyle(.white)
                            .background(Color.accentColor)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }

                if viewModel.canDeleteAll {
                    if viewModel.isDeleting {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    } else {
                        Button(role: .destructive) {
                            viewModel.showDeleteAllConfirmation = true
                        } label: {
                            Label(String(localized: "Delete All"), systemImage: "trash")
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .foregroundStyle(.white)
                                .background(.red)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                        .tint(.red)
                    }
                }

                if let error = viewModel.downloadError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }

                if let error = viewModel.deleteError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }
            }
            .padding()
            .background(.bar)
        }
    }

    @ViewBuilder
    private func buildContent() -> some View {
        if viewModel.isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(viewModel.availableDeviceTypes) { device in
                let sets = viewModel.sets(for: device)
                Button {
                    homeCoordinator.navigateToScreenshotResolution(
                        device: device,
                        sets: sets,
                        account: viewModel.account,
                        appStoreState: viewModel.appStoreState
                    )
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: device.icon)
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .frame(width: 32)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(device.title)
                                .font(.body)
                                .foregroundStyle(.primary)

                            if sets.isEmpty {
                                Text("No screenshots")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            } else {
                                let total = sets.reduce(0) { $0 + $1.screenshots.count }
                                Text("\(sets.count) sizes, \(total) screenshots")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .disabled(sets.isEmpty)
                .foregroundStyle(.primary)
            }
            
        }
    }
}
