import SwiftUI

// MARK: - Device Type

enum ScreenshotDeviceType: String, CaseIterable, Identifiable, Hashable {
    case iPhone
    case iPad
    case appleWatch
    case iMessage

    var id: String { rawValue }

    var title: String {
        switch self {
        case .iPhone:     return "iPhone"
        case .iPad:       return "iPad"
        case .appleWatch: return "Apple Watch"
        case .iMessage:   return "iMessage App"
        }
    }

    var icon: String {
        switch self {
        case .iPhone:     return "iphone"
        case .iPad:       return "ipad"
        case .appleWatch: return "applewatch"
        case .iMessage:   return "message.fill"
        }
    }
}

// MARK: - Factory

@MainActor
struct ScreenshotPreviewViewFactory {
    static func build(versionId: String, account: AccountModel) -> some View {
        ScreenshotPreviewEntry(versionId: versionId, account: account)
    }
}

// MARK: - Entry

private struct ScreenshotPreviewEntry: View {
    let versionId: String
    let account: AccountModel

    @StateObject private var viewModel: ScreenshotPreviewViewModel

    init(versionId: String, account: AccountModel) {
        self.versionId = versionId
        self.account = account
        _viewModel = StateObject(wrappedValue: ScreenshotPreviewViewModel(versionId: versionId, account: account))
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

    private let versionId: String
    private let account: AccountModel
    private let keychain: KeyStorable

    init(versionId: String, account: AccountModel, keychain: KeyStorable = KeychainStorable.shared) {
        self.versionId = versionId
        self.account = account
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
            let localizations = try await connection.fetchLocalizations(versionId: versionId)
            guard let locId = localizations.first?.id else {
                isLoading = false
                return
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
    }

    @ViewBuilder
    private func buildContent() -> some View {
        if viewModel.isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(ScreenshotDeviceType.allCases) { device in
                let sets = viewModel.sets(for: device)
                Button {
                    homeCoordinator.navigateToScreenshotResolution(
                        device: device,
                        sets: sets
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
