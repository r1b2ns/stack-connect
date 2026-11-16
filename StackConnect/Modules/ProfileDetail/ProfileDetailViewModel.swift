import Foundation
import StackProtocols

// MARK: - Notifications

extension Notification.Name {
    static let profileDeleted = Notification.Name("StackConnect.profileDeleted")
}

// MARK: - Protocol

@MainActor
protocol ProfileDetailViewModelProtocol: ObservableObject {
    var uiState: ProfileDetailUiState { get set }
    func prepareDownload() async -> URL?
    func delete() async -> Bool
}

// MARK: - UiState

struct ProfileDetailUiState {
    var account: AccountModel
    var profile: ProvisioningProfileModel
    var isPreparingDownload = false
    var isDeleting = false
    var errorMessage: String?
}

// MARK: - Implementation

@MainActor
final class ProfileDetailViewModel: ProfileDetailViewModelProtocol {

    @Published var uiState: ProfileDetailUiState

    private let keychain: KeyStorable
    private let analytics: AnalyticsTracking

    init(
        account: AccountModel,
        profile: ProvisioningProfileModel,
        keychain: KeyStorable = KeychainStorable.shared,
        analytics: AnalyticsTracking = AnalyticsService.shared
    ) {
        self.uiState = ProfileDetailUiState(account: account, profile: profile)
        self.keychain = keychain
        self.analytics = analytics
    }

    func prepareDownload() async -> URL? {
        analytics.track(.buttonTap(.download, on: .profileDetail))
        let url = await performDownload()
        analytics.track(.action(.downloadProfile, on: .profileDetail, result: url != nil ? .success : .failure))
        return url
    }

    private func performDownload() async -> URL? {
        guard let connection = makeConnection() else { return nil }

        uiState.isPreparingDownload = true
        uiState.errorMessage = nil
        defer { uiState.isPreparingDownload = false }

        do {
            guard let base64 = try await connection.fetchProfileContent(id: uiState.profile.id),
                  let data = Data(base64Encoded: base64) else {
                uiState.errorMessage = String(localized: "Profile content unavailable")
                return nil
            }

            let safeName = uiState.profile.name
                .replacingOccurrences(of: "/", with: "-")
                .replacingOccurrences(of: ":", with: "-")
            let fileName = safeName.isEmpty ? "profile.mobileprovision" : "\(safeName).mobileprovision"
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)

            try data.write(to: url, options: .atomic)
            Log.print.info("[ProfileDetail] Prepared download at \(url.lastPathComponent)")
            return url
        } catch {
            uiState.errorMessage = AppleAPIErrorTranslator.friendlyMessage(for: error)
            Log.print.error("[ProfileDetail] Download prep failed: \(error.localizedDescription)")
            return nil
        }
    }

    func delete() async -> Bool {
        analytics.track(.buttonTap(.confirmDelete, on: .profileDetail))
        let deleted = await performDelete()
        analytics.track(.action(.deleteProfile, on: .profileDetail, result: deleted ? .success : .failure))
        return deleted
    }

    private func performDelete() async -> Bool {
        guard let connection = makeConnection() else { return false }

        uiState.isDeleting = true
        uiState.errorMessage = nil
        defer { uiState.isDeleting = false }

        do {
            try await connection.deleteProfile(id: uiState.profile.id)
            NotificationCenter.default.post(name: .profileDeleted, object: uiState.profile.id)
            return true
        } catch {
            uiState.errorMessage = AppleAPIErrorTranslator.friendlyMessage(for: error)
            Log.print.error("[ProfileDetail] Delete failed: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Private

    private func makeConnection() -> AppleAccountConnection? {
        guard let credentials: AppleCredentials = keychain.object(forKey: "credentials.\(uiState.account.id)") else {
            uiState.errorMessage = String(localized: "No credentials found for this account")
            return nil
        }
        return AppleAccountConnection(credentials: credentials)
    }
}
