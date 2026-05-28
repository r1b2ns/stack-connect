import Foundation

// MARK: - Notifications

extension Notification.Name {
    static let profileCreated = Notification.Name("StackConnect.profileCreated")
}

// MARK: - Type catalog

enum ProfileTypeSection: String, CaseIterable, Identifiable {
    case iOS, macOS, tvOS, macCatalyst

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .iOS:         return "iOS, tvOS, visionOS, watchOS"
        case .macOS:       return "macOS"
        case .tvOS:        return "tvOS"
        case .macCatalyst: return "Mac Catalyst"
        }
    }
}

struct ProfileTypeOption: Identifiable, Hashable {
    let raw: String                 // API rawValue, e.g. "IOS_APP_DEVELOPMENT"
    let displayName: String
    let section: ProfileTypeSection

    var id: String { raw }

    /// Development and Ad Hoc profiles must include devices; the others must not.
    var requiresDevices: Bool {
        raw.hasSuffix("_DEVELOPMENT") || raw.hasSuffix("_ADHOC")
    }

    /// "Development" profiles must use development certificates; everything else uses distribution.
    var isDevelopment: Bool {
        raw.hasSuffix("_DEVELOPMENT")
    }
}

enum ProfileTypeCatalog {
    static let all: [ProfileTypeOption] = [
        // iOS family (covers tvOS, watchOS, visionOS via the same bundle IDs).
        .init(raw: "IOS_APP_DEVELOPMENT", displayName: "iOS App Development", section: .iOS),
        .init(raw: "IOS_APP_STORE",       displayName: "iOS App Store",       section: .iOS),
        .init(raw: "IOS_APP_ADHOC",       displayName: "iOS Ad Hoc",          section: .iOS),
        .init(raw: "IOS_APP_INHOUSE",     displayName: "iOS In-House",        section: .iOS),
        // tvOS-specific (Apple keeps these separate even though IOS_* covers most cases).
        .init(raw: "TVOS_APP_DEVELOPMENT", displayName: "tvOS App Development", section: .tvOS),
        .init(raw: "TVOS_APP_STORE",       displayName: "tvOS App Store",       section: .tvOS),
        .init(raw: "TVOS_APP_ADHOC",       displayName: "tvOS Ad Hoc",          section: .tvOS),
        .init(raw: "TVOS_APP_INHOUSE",     displayName: "tvOS In-House",        section: .tvOS),
        // macOS
        .init(raw: "MAC_APP_DEVELOPMENT", displayName: "Mac Development",      section: .macOS),
        .init(raw: "MAC_APP_STORE",       displayName: "Mac App Store",        section: .macOS),
        .init(raw: "MAC_APP_DIRECT",      displayName: "Mac Direct",           section: .macOS),
        // Mac Catalyst
        .init(raw: "MAC_CATALYST_APP_DEVELOPMENT", displayName: "Mac Catalyst Development", section: .macCatalyst),
        .init(raw: "MAC_CATALYST_APP_STORE",       displayName: "Mac Catalyst App Store",   section: .macCatalyst),
        .init(raw: "MAC_CATALYST_APP_DIRECT",      displayName: "Mac Catalyst Direct",      section: .macCatalyst)
    ]
}

// MARK: - Step

enum CreateProfileStep: Int, Hashable, CaseIterable {
    case selectType
    case selectBundleId
    case selectCertificates
    case selectDevices
    case nameAndConfirm
    case generated

    var displayName: String {
        switch self {
        case .selectType:         return String(localized: "Type")
        case .selectBundleId:     return String(localized: "Bundle ID")
        case .selectCertificates: return String(localized: "Certificates")
        case .selectDevices:      return String(localized: "Devices")
        case .nameAndConfirm:     return String(localized: "Name")
        case .generated:          return String(localized: "Done")
        }
    }
}

// MARK: - Protocol

@MainActor
protocol CreateProfileViewModelProtocol: ObservableObject {
    var uiState: CreateProfileUiState { get set }
    func loadResources() async
    func selectType(_ option: ProfileTypeOption)
    func selectBundleId(_ bundle: BundleIdentifierModel)
    func toggleCertificate(id: String)
    func toggleDevice(id: String)
    func goNextFromCertificates()
    func goNextFromDevices()
    func submit() async
    func goBack()
    func prepareDownload() -> URL?
}

// MARK: - UiState

struct CreateProfileUiState {
    var account: AccountModel
    var step: CreateProfileStep = .selectType

    var selectedType: ProfileTypeOption?
    var name: String = ""
    var selectedBundleId: BundleIdentifierModel?
    var selectedCertificateIds: Set<String> = []
    var selectedDeviceIds: Set<String> = []

    var bundleIds: [BundleIdentifierModel] = []
    var certificates: [CertificateModel] = []
    var devices: [DeviceModel] = []

    var isLoadingResources = false
    var showAllResources = false

    var isCreating = false
    var createdProfile: ProvisioningProfileModel?
    var createdContentBase64: String?
    var errorMessage: String?

    // MARK: - Derived (filtered) views

    var filteredBundleIds: [BundleIdentifierModel] {
        guard let type = selectedType, !showAllResources else { return bundleIds }
        return bundleIds.filter { matches(bundle: $0, profileType: type) }
    }

    var filteredCertificates: [CertificateModel] {
        guard let type = selectedType, !showAllResources else {
            return certificates.filter { !$0.isExpired }
        }
        return certificates.filter { !$0.isExpired && matches(cert: $0, profileType: type) }
    }

    var filteredDevices: [DeviceModel] {
        let enabled = devices.filter { $0.isEnabled }
        guard let type = selectedType, !showAllResources else { return enabled }
        return enabled.filter { matches(device: $0, profileType: type) }
    }

    private func matches(bundle: BundleIdentifierModel, profileType: ProfileTypeOption) -> Bool {
        let p = bundle.platform
        if p == "UNIVERSAL" { return true }
        if profileType.section == .macOS && p == "MAC_OS" { return true }
        // iOS / tvOS / Mac Catalyst use IOS-platform bundle IDs (Apple unified them).
        if [.iOS, .tvOS, .macCatalyst].contains(profileType.section) && p == "IOS" { return true }
        return false
    }

    /// Apple's compatibility rules between certificate type and profile type:
    /// - `DEVELOPMENT` / `DISTRIBUTION` (Apple Development / Distribution) are cross-platform.
    /// - `IOS_DEVELOPMENT` / `IOS_DISTRIBUTION` cover iOS, tvOS, watchOS, visionOS and Mac Catalyst.
    /// - `MAC_APP_*` and `MAC_INSTALLER_DISTRIBUTION` only work with macOS profiles.
    private func matches(cert: CertificateModel, profileType: ProfileTypeOption) -> Bool {
        let t = cert.certificateType
        let isDev = profileType.isDevelopment
        let section = profileType.section

        if isDev {
            if t == "DEVELOPMENT" { return true }                          // Apple Development (universal)
            if section == .macOS { return t == "MAC_APP_DEVELOPMENT" }
            return t == "IOS_DEVELOPMENT"                                  // iOS / tvOS / Mac Catalyst
        } else {
            if t == "DISTRIBUTION" { return true }                         // Apple Distribution (universal)
            if section == .macOS {
                return t == "MAC_APP_DISTRIBUTION" || t == "MAC_INSTALLER_DISTRIBUTION"
            }
            return t == "IOS_DISTRIBUTION"                                 // iOS / tvOS / Mac Catalyst
        }
    }

    private func matches(device: DeviceModel, profileType: ProfileTypeOption) -> Bool {
        if profileType.section == .macOS { return device.platform == "MAC_OS" }
        return device.platform == "IOS" || device.platform == nil
    }
}

// MARK: - Implementation

@MainActor
final class CreateProfileViewModel: CreateProfileViewModelProtocol {

    @Published var uiState: CreateProfileUiState

    private let keychain: KeyStorable

    init(
        account: AccountModel,
        keychain: KeyStorable = KeychainStorable.shared
    ) {
        self.uiState = CreateProfileUiState(account: account)
        self.keychain = keychain
    }

    // MARK: - Loading

    func loadResources() async {
        guard !uiState.isLoadingResources, uiState.bundleIds.isEmpty else { return }
        guard let connection = makeConnection() else { return }

        uiState.isLoadingResources = true
        uiState.errorMessage = nil

        async let bundleIdsTask = connection.fetchBundleIds()
        async let certificatesTask = connection.fetchCertificates()
        async let devicesTask = connection.fetchDevices()

        do {
            let (bundleIds, certificates, devices) = try await (bundleIdsTask, certificatesTask, devicesTask)
            uiState.bundleIds = bundleIds
            uiState.certificates = certificates
            uiState.devices = devices
            Log.print.info("[CreateProfile] Loaded \(bundleIds.count) bundles, \(certificates.count) certs, \(devices.count) devices")
        } catch {
            uiState.errorMessage = AppleAPIErrorTranslator.friendlyMessage(for: error)
            Log.print.error("[CreateProfile] Load resources failed: \(error.localizedDescription)")
        }

        uiState.isLoadingResources = false
    }

    // MARK: - Step navigation

    func selectType(_ option: ProfileTypeOption) {
        uiState.selectedType = option
        uiState.selectedBundleId = nil
        uiState.selectedCertificateIds = []
        uiState.selectedDeviceIds = []
        uiState.errorMessage = nil
        uiState.step = .selectBundleId
    }

    func selectBundleId(_ bundle: BundleIdentifierModel) {
        uiState.selectedBundleId = bundle
        uiState.errorMessage = nil
        uiState.step = .selectCertificates
    }

    func toggleCertificate(id: String) {
        if uiState.selectedCertificateIds.contains(id) {
            uiState.selectedCertificateIds.remove(id)
        } else {
            uiState.selectedCertificateIds.insert(id)
        }
    }

    func toggleDevice(id: String) {
        if uiState.selectedDeviceIds.contains(id) {
            uiState.selectedDeviceIds.remove(id)
        } else {
            uiState.selectedDeviceIds.insert(id)
        }
    }

    func goNextFromCertificates() {
        guard !uiState.selectedCertificateIds.isEmpty else { return }
        if uiState.selectedType?.requiresDevices == true {
            uiState.step = .selectDevices
        } else {
            uiState.step = .nameAndConfirm
        }
    }

    func goNextFromDevices() {
        uiState.step = .nameAndConfirm
    }

    func goBack() {
        switch uiState.step {
        case .selectType, .generated:
            break
        case .selectBundleId:
            uiState.step = .selectType
        case .selectCertificates:
            uiState.step = .selectBundleId
        case .selectDevices:
            uiState.step = .selectCertificates
        case .nameAndConfirm:
            uiState.step = (uiState.selectedType?.requiresDevices == true) ? .selectDevices : .selectCertificates
        }
        uiState.errorMessage = nil
    }

    // MARK: - Submit

    func submit() async {
        guard let type = uiState.selectedType,
              let bundle = uiState.selectedBundleId,
              !uiState.selectedCertificateIds.isEmpty,
              !uiState.name.trimmingCharacters(in: .whitespaces).isEmpty else {
            uiState.errorMessage = String(localized: "Missing required fields")
            return
        }

        if type.requiresDevices && uiState.selectedDeviceIds.isEmpty {
            uiState.errorMessage = String(localized: "This profile type requires at least one device")
            return
        }

        guard let connection = makeConnection() else { return }

        uiState.isCreating = true
        uiState.errorMessage = nil

        do {
            let result = try await connection.createProfile(
                name: uiState.name.trimmingCharacters(in: .whitespaces),
                profileTypeRaw: type.raw,
                bundleIdId: bundle.id,
                certificateIds: Array(uiState.selectedCertificateIds),
                deviceIds: type.requiresDevices ? Array(uiState.selectedDeviceIds) : []
            )

            uiState.createdProfile = result.profile
            uiState.createdContentBase64 = result.content
            uiState.step = .generated

            NotificationCenter.default.post(name: .profileCreated, object: result.profile)
            Log.print.info("[CreateProfile] Created \(result.profile.id)")
        } catch {
            uiState.errorMessage = AppleAPIErrorTranslator.friendlyMessage(for: error)
            Log.print.error("[CreateProfile] Failed: \(error.localizedDescription)")
        }

        uiState.isCreating = false
    }

    // MARK: - Download

    func prepareDownload() -> URL? {
        guard let base64 = uiState.createdContentBase64,
              let data = Data(base64Encoded: base64),
              let profile = uiState.createdProfile else {
            uiState.errorMessage = String(localized: "Profile content unavailable")
            return nil
        }

        let safeName = profile.name
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        let fileName = safeName.isEmpty ? "profile.mobileprovision" : "\(safeName).mobileprovision"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)

        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            uiState.errorMessage = error.localizedDescription
            Log.print.error("[CreateProfile] Write failed: \(error.localizedDescription)")
            return nil
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
