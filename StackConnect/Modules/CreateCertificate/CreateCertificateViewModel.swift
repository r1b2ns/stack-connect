import Foundation

// MARK: - Notifications

extension Notification.Name {
    static let certificateCreated = Notification.Name("StackConnect.certificateCreated")
}

// MARK: - Type catalog (UI-facing list, matches developer.apple.com layout)

enum CertificateTypeSection: String, CaseIterable, Identifiable {
    case software
    case services

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .software: return String(localized: "Software")
        case .services: return String(localized: "Services")
        }
    }
}

enum CertificateRelationshipKind {
    case passTypeId
    case merchantId
}

enum CertificateTypeOption: String, CaseIterable, Identifiable, Hashable {
    // Software
    case appleDevelopment
    case appleDistribution
    case iosAppDevelopment
    case iosDistribution
    case macDevelopment
    case macAppDistribution
    case macInstallerDistribution
    case developerIDInstaller
    case developerIDApplication

    // Services
    case apnsSslSandbox
    case apnsSslSandboxProduction
    case passTypeID
    case orderTypeID
    case websitePushID
    case swiftPackageCollection
    case swiftPackage
    case watchKitServices
    case voipServices
    case applePayPaymentProcessing
    case applePayMerchantIdentity

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .appleDevelopment:               return String(localized: "Apple Development")
        case .appleDistribution:              return String(localized: "Apple Distribution")
        case .iosAppDevelopment:              return String(localized: "iOS App Development")
        case .iosDistribution:                return String(localized: "iOS Distribution (App Store Connect and Ad Hoc)")
        case .macDevelopment:                 return String(localized: "Mac Development")
        case .macAppDistribution:             return String(localized: "Mac App Distribution")
        case .macInstallerDistribution:       return String(localized: "Mac Installer Distribution")
        case .developerIDInstaller:           return String(localized: "Developer ID Installer")
        case .developerIDApplication:         return String(localized: "Developer ID Application")

        case .apnsSslSandbox:                 return String(localized: "Apple Push Notification service SSL (Sandbox)")
        case .apnsSslSandboxProduction:       return String(localized: "Apple Push Notification service SSL (Sandbox & Production)")
        case .passTypeID:                     return String(localized: "Pass Type ID Certificate")
        case .orderTypeID:                    return String(localized: "Order Type ID Certificate")
        case .websitePushID:                  return String(localized: "Website Push ID Certificate")
        case .swiftPackageCollection:         return String(localized: "Swift Package Collection Certificate")
        case .swiftPackage:                   return String(localized: "Swift Package Certificate")
        case .watchKitServices:               return String(localized: "WatchKit Services Certificate")
        case .voipServices:                   return String(localized: "VoIP Services Certificate")
        case .applePayPaymentProcessing:      return String(localized: "Apple Pay Payment Processing Certificate")
        case .applePayMerchantIdentity:       return String(localized: "Apple Pay Merchant Identity Certificate")
        }
    }

    var section: CertificateTypeSection {
        switch self {
        case .appleDevelopment, .appleDistribution, .iosAppDevelopment, .iosDistribution,
             .macDevelopment, .macAppDistribution, .macInstallerDistribution,
             .developerIDInstaller, .developerIDApplication:
            return .software
        default:
            return .services
        }
    }

    /// Raw value accepted by `POST /v1/certificates`. `nil` means the API does not expose this type.
    var apiType: String? {
        switch self {
        case .appleDevelopment:         return "DEVELOPMENT"
        case .appleDistribution:        return "DISTRIBUTION"
        case .iosAppDevelopment:        return "IOS_DEVELOPMENT"
        case .iosDistribution:          return "IOS_DISTRIBUTION"
        case .macDevelopment:           return "MAC_APP_DEVELOPMENT"
        case .macAppDistribution:       return "MAC_APP_DISTRIBUTION"
        case .macInstallerDistribution: return "MAC_INSTALLER_DISTRIBUTION"
        case .developerIDApplication:   return "DEVELOPER_ID_APPLICATION_G2"
        case .passTypeID:               return "PASS_TYPE_ID"
        case .applePayMerchantIdentity: return "APPLE_PAY_MERCHANT_IDENTITY"
        default:                        return nil
        }
    }

    var isSupportedByAPI: Bool { apiType != nil }

    /// Some types require an extra relationship ID (`passTypeId` / `merchantId`).
    var relationshipKind: CertificateRelationshipKind? {
        switch self {
        case .passTypeID:               return .passTypeId
        case .applePayMerchantIdentity: return .merchantId
        default:                        return nil
        }
    }
}

// MARK: - Step

enum CreateCertificateStep: Int, Hashable {
    case selectType
    case uploadCSR
    case generated

    var displayName: String {
        switch self {
        case .selectType: return String(localized: "Type")
        case .uploadCSR:  return String(localized: "Upload CSR")
        case .generated:  return String(localized: "Done")
        }
    }
}

// MARK: - Protocol

@MainActor
protocol CreateCertificateViewModelProtocol: ObservableObject {
    var uiState: CreateCertificateUiState { get set }
    func selectType(_ option: CertificateTypeOption)
    func loadCSR(from url: URL) async
    func submit() async
    func goBack()
    func prepareDownload() -> URL?
}

// MARK: - UiState

struct CreateCertificateUiState {
    var account: AccountModel
    var step: CreateCertificateStep = .selectType
    var selectedType: CertificateTypeOption?
    var csrContent: String?
    var csrFileName: String?
    var relationshipId: String = ""
    var isCreating = false
    var createdCertificate: CertificateModel?
    var createdContentBase64: String?
    var errorMessage: String?
}

// MARK: - Implementation

@MainActor
final class CreateCertificateViewModel: CreateCertificateViewModelProtocol {

    @Published var uiState: CreateCertificateUiState

    private let keychain: KeyStorable

    init(
        account: AccountModel,
        keychain: KeyStorable = KeychainStorable.shared
    ) {
        self.uiState = CreateCertificateUiState(account: account)
        self.keychain = keychain
    }

    // MARK: - Step navigation

    func selectType(_ option: CertificateTypeOption) {
        guard option.isSupportedByAPI else { return }
        uiState.selectedType = option
        uiState.errorMessage = nil
        uiState.step = .uploadCSR
    }

    func goBack() {
        switch uiState.step {
        case .selectType:
            break
        case .uploadCSR:
            uiState.step = .selectType
            uiState.csrContent = nil
            uiState.csrFileName = nil
            uiState.relationshipId = ""
            uiState.errorMessage = nil
        case .generated:
            break
        }
    }

    // MARK: - CSR

    func loadCSR(from url: URL) async {
        uiState.errorMessage = nil
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        do {
            let raw = try String(contentsOf: url, encoding: .utf8)
            uiState.csrContent = Self.normalizeCSR(raw)
            uiState.csrFileName = url.lastPathComponent
            Log.print.info("[CreateCertificate] Loaded CSR: \(url.lastPathComponent) (\(raw.count) bytes)")
        } catch {
            uiState.errorMessage = String(localized: "Failed to read CSR file: \(error.localizedDescription)")
            Log.print.error("[CreateCertificate] CSR read failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Submit

    func submit() async {
        guard let selectedType = uiState.selectedType,
              let apiType = selectedType.apiType,
              let csrContent = uiState.csrContent, !csrContent.isEmpty else {
            uiState.errorMessage = String(localized: "Select a type and load a valid CSR file")
            return
        }

        guard let credentials: AppleCredentials = keychain.object(forKey: "credentials.\(uiState.account.id)") else {
            uiState.errorMessage = String(localized: "No credentials found for this account")
            return
        }

        uiState.isCreating = true
        uiState.errorMessage = nil

        let connection = AppleAccountConnection(credentials: credentials)
        let passTypeId = selectedType.relationshipKind == .passTypeId ? uiState.relationshipId : nil
        let merchantId = selectedType.relationshipKind == .merchantId ? uiState.relationshipId : nil

        do {
            let result = try await connection.createCertificate(
                csrContent: csrContent,
                certificateTypeRaw: apiType,
                passTypeId: passTypeId,
                merchantId: merchantId
            )
            uiState.createdCertificate = result.certificate
            uiState.createdContentBase64 = result.content
            uiState.step = .generated

            NotificationCenter.default.post(
                name: .certificateCreated,
                object: result.certificate
            )

            Log.print.info("[CreateCertificate] Success: \(result.certificate.id)")
        } catch {
            uiState.errorMessage = error.localizedDescription
            Log.print.error("[CreateCertificate] Create failed: \(error.localizedDescription)")
        }

        uiState.isCreating = false
    }

    // MARK: - Download

    func prepareDownload() -> URL? {
        guard let base64 = uiState.createdContentBase64,
              let data = Data(base64Encoded: base64),
              let certificate = uiState.createdCertificate else {
            uiState.errorMessage = String(localized: "Certificate content unavailable")
            return nil
        }

        let safeName = certificate.displayName
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        let fileName = safeName.isEmpty ? "certificate.cer" : "\(safeName).cer"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)

        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            uiState.errorMessage = error.localizedDescription
            Log.print.error("[CreateCertificate] Write failed: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Private

    /// Strips PEM header/footer and whitespace so we send the API only the base64 body.
    static func normalizeCSR(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = "-----BEGIN CERTIFICATE REQUEST-----([\\s\\S]*?)-----END CERTIFICATE REQUEST-----"
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
           let bodyRange = Range(match.range(at: 1), in: trimmed) {
            return String(trimmed[bodyRange])
                .components(separatedBy: .whitespacesAndNewlines)
                .joined()
        }
        return trimmed.components(separatedBy: .whitespacesAndNewlines).joined()
    }
}
