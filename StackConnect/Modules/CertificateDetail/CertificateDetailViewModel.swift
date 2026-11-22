import Foundation
import StackProtocols

// MARK: - Protocol

@MainActor
protocol CertificateDetailViewModelProtocol: ObservableObject {
    var uiState: CertificateDetailUiState { get set }
    func prepareDownload() async -> URL?
    func revoke() async -> Bool
}

// MARK: - UiState

struct CertificateDetailUiState {
    var account: AccountModel
    var certificate: CertificateModel
    var isPreparingDownload = false
    var isRevoking = false
    var errorMessage: String?
}

// MARK: - Notifications

extension Notification.Name {
    static let certificateRevoked = Notification.Name("StackConnect.certificateRevoked")
}

// MARK: - Implementation

@MainActor
final class CertificateDetailViewModel: CertificateDetailViewModelProtocol {

    @Published var uiState: CertificateDetailUiState

    private let keychain: KeyStorable
    private let analytics: AnalyticsTracking

    init(
        account: AccountModel,
        certificate: CertificateModel,
        keychain: KeyStorable = KeychainStorable.shared,
        analytics: AnalyticsTracking = AnalyticsService.shared
    ) {
        self.uiState = CertificateDetailUiState(account: account, certificate: certificate)
        self.keychain = keychain
        self.analytics = analytics
    }

    func prepareDownload() async -> URL? {
        analytics.track(.buttonTap(.download, on: .certificateDetail))
        let url = await performDownload()
        analytics.track(.action(.downloadCertificate, on: .certificateDetail, result: url != nil ? .success : .failure))
        return url
    }

    private func performDownload() async -> URL? {
        guard let connection = makeConnection() else { return nil }

        uiState.isPreparingDownload = true
        uiState.errorMessage = nil
        defer { uiState.isPreparingDownload = false }

        do {
            guard let base64 = try await connection.fetchCertificateContent(id: uiState.certificate.id),
                  let data = Data(base64Encoded: base64) else {
                uiState.errorMessage = String(localized: "Certificate content unavailable")
                return nil
            }

            let safeName = uiState.certificate.displayName
                .replacingOccurrences(of: "/", with: "-")
                .replacingOccurrences(of: ":", with: "-")
            let fileName = safeName.isEmpty ? "certificate.cer" : "\(safeName).cer"
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)

            try data.write(to: url, options: .atomic)
            Log.print.info("[CertificateDetail] Prepared download at \(url.lastPathComponent)")
            return url
        } catch {
            uiState.errorMessage = error.userFacingMessage
            Log.print.error("[CertificateDetail] Download prep failed: \(error.localizedDescription)")
            return nil
        }
    }

    func revoke() async -> Bool {
        analytics.track(.buttonTap(.confirmRevoke, on: .certificateDetail))
        let succeeded = await performRevoke()
        analytics.track(.action(.revokeCertificate, on: .certificateDetail, result: succeeded ? .success : .failure))
        return succeeded
    }

    private func performRevoke() async -> Bool {
        guard let connection = makeConnection() else { return false }

        uiState.isRevoking = true
        uiState.errorMessage = nil
        defer { uiState.isRevoking = false }

        do {
            try await connection.revokeCertificate(id: uiState.certificate.id)
            NotificationCenter.default.post(
                name: .certificateRevoked,
                object: uiState.certificate.id
            )
            return true
        } catch {
            uiState.errorMessage = error.userFacingMessage
            Log.print.error("[CertificateDetail] Revoke failed: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Private

    private func makeConnection() -> AppleAccountConnection? {
        guard let credentials: AppleCredentials = keychain.object(forKey: "credentials.\(uiState.account.id)") else {
            uiState.errorMessage = String(localized: "No credentials found for this account")
            Log.print.error("[CertificateDetail] No credentials for account: \(self.uiState.account.name)")
            return nil
        }
        return AppleAccountConnection(credentials: credentials)
    }
}
