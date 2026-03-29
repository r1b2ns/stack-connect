import Foundation

// MARK: - Protocol

@MainActor
protocol AppReviewInfoViewModelProtocol: ObservableObject {
    var uiState: AppReviewInfoUiState { get set }
    func loadReviewDetail() async
    func save() async
}

// MARK: - UiState

struct AppReviewInfoUiState {
    var versionId: String
    var account: AccountModel
    var isLoading = false
    var isSaving = false
    var error: String?
    var didSave = false

    // Sign-In Information
    var demoAccountName = ""
    var demoAccountPassword = ""
    var isDemoAccountRequired = false

    // Contact Information
    var contactFirstName = ""
    var contactLastName = ""
    var contactEmail = ""
    var contactPhone = ""

    // Notes
    var notes = ""

    var reviewDetailId: String?
}

// MARK: - Implementation

@MainActor
final class AppReviewInfoViewModel: AppReviewInfoViewModelProtocol {

    @Published var uiState: AppReviewInfoUiState

    private let keychain: KeyStorable

    init(
        versionId: String,
        account: AccountModel,
        keychain: KeyStorable = KeychainStorable.shared
    ) {
        self.uiState = AppReviewInfoUiState(versionId: versionId, account: account)
        self.keychain = keychain
    }

    func loadReviewDetail() async {
        uiState.isLoading = true

        guard let connection = createConnection() else {
            uiState.isLoading = false
            return
        }

        do {
            if let detail = try await connection.fetchAppReviewDetail(versionId: uiState.versionId) {
                uiState.reviewDetailId = detail.id
                uiState.demoAccountName = detail.demoAccountName ?? ""
                uiState.demoAccountPassword = detail.demoAccountPassword ?? ""
                uiState.isDemoAccountRequired = detail.isDemoAccountRequired ?? false
                uiState.contactFirstName = detail.contactFirstName ?? ""
                uiState.contactLastName = detail.contactLastName ?? ""
                uiState.contactEmail = detail.contactEmail ?? ""
                uiState.contactPhone = detail.contactPhone ?? ""
                uiState.notes = detail.notes ?? ""
            }
        } catch {
            Log.print.error("[AppReviewInfo] Load failed: \(error.localizedDescription)")
        }

        uiState.isLoading = false
    }

    func save() async {
        guard let reviewDetailId = uiState.reviewDetailId else { return }

        uiState.isSaving = true
        uiState.error = nil

        guard let connection = createConnection() else {
            uiState.isSaving = false
            return
        }

        do {
            let model = AppReviewDetailModel(
                id: reviewDetailId,
                contactFirstName: uiState.contactFirstName,
                contactLastName: uiState.contactLastName,
                contactEmail: uiState.contactEmail,
                contactPhone: uiState.contactPhone,
                notes: uiState.notes,
                demoAccountName: uiState.demoAccountName,
                demoAccountPassword: uiState.demoAccountPassword,
                isDemoAccountRequired: uiState.isDemoAccountRequired
            )

            try await connection.updateAppReviewDetail(model: model)
            uiState.didSave = true
            Log.print.info("[AppReviewInfo] Saved review detail")
        } catch {
            uiState.error = error.localizedDescription
            Log.print.error("[AppReviewInfo] Save failed: \(error.localizedDescription)")
        }

        uiState.isSaving = false
    }

    private func createConnection() -> AppleAccountConnection? {
        guard let credentials: AppleCredentials = keychain.object(forKey: "credentials.\(uiState.account.id)") else {
            return nil
        }
        return AppleAccountConnection(credentials: credentials)
    }
}
