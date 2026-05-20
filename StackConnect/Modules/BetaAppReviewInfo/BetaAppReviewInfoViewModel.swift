import Foundation

// MARK: - Protocol

@MainActor
protocol BetaAppReviewInfoViewModelProtocol: ObservableObject {
    var uiState: BetaAppReviewInfoUiState { get set }
    func load() async
    func save() async
}

// MARK: - UiState

struct BetaAppReviewInfoUiState {
    var appId: String
    var account: AccountModel
    var isLoading = false
    var isSaving = false
    var error: String?
    var didSave = false

    // Beta App Localization
    var betaDescription = ""
    var feedbackEmail = ""
    var localizationId: String?
    var locale: String = "en-US"

    // Beta App Review Detail
    var reviewDetailId: String?

    // Contact Information
    var contactFirstName = ""
    var contactLastName = ""
    var contactEmail = ""
    var contactPhone = ""

    // Sign-In Information
    var isDemoAccountRequired = false
    var demoAccountName = ""
    var demoAccountPassword = ""

    // Validation
    var didAttemptSave = false

    var isBetaDescriptionInvalid: Bool {
        didAttemptSave && betaDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    var isFeedbackEmailInvalid: Bool {
        didAttemptSave && feedbackEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    var isContactFirstNameInvalid: Bool {
        didAttemptSave && contactFirstName.trimmingCharacters(in: .whitespaces).isEmpty
    }
    var isContactLastNameInvalid: Bool {
        didAttemptSave && contactLastName.trimmingCharacters(in: .whitespaces).isEmpty
    }
    var isContactPhoneInvalid: Bool {
        didAttemptSave && contactPhone.trimmingCharacters(in: .whitespaces).isEmpty
    }
    var isContactEmailInvalid: Bool {
        didAttemptSave && contactEmail.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var hasValidationErrors: Bool {
        betaDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || feedbackEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || contactFirstName.trimmingCharacters(in: .whitespaces).isEmpty
            || contactLastName.trimmingCharacters(in: .whitespaces).isEmpty
            || contactPhone.trimmingCharacters(in: .whitespaces).isEmpty
            || contactEmail.trimmingCharacters(in: .whitespaces).isEmpty
    }
}

// MARK: - Implementation

@MainActor
final class BetaAppReviewInfoViewModel: BetaAppReviewInfoViewModelProtocol {

    @Published var uiState: BetaAppReviewInfoUiState

    private let keychain: KeyStorable

    init(
        appId: String,
        account: AccountModel,
        keychain: KeyStorable = KeychainStorable.shared
    ) {
        self.uiState = BetaAppReviewInfoUiState(appId: appId, account: account)
        self.keychain = keychain
    }

    func load() async {
        uiState.isLoading = true
        uiState.error = nil

        guard let connection = createConnection() else {
            uiState.isLoading = false
            return
        }

        do {
            async let detailResult = connection.fetchBetaAppReviewDetail(appId: uiState.appId)
            async let localizationsResult = connection.fetchBetaAppLocalizations(appId: uiState.appId)

            if let detail = try await detailResult {
                uiState.reviewDetailId = detail.id
                uiState.contactFirstName = detail.contactFirstName ?? ""
                uiState.contactLastName = detail.contactLastName ?? ""
                uiState.contactEmail = detail.contactEmail ?? ""
                uiState.contactPhone = detail.contactPhone ?? ""
                uiState.isDemoAccountRequired = detail.isDemoAccountRequired ?? false
                uiState.demoAccountName = detail.demoAccountName ?? ""
                uiState.demoAccountPassword = detail.demoAccountPassword ?? ""
            }

            let localizations = try await localizationsResult
            let preferred = localizations.first(where: { $0.locale == "en-US" }) ?? localizations.first
            if let preferred {
                uiState.localizationId = preferred.id
                uiState.locale = preferred.locale
                uiState.feedbackEmail = preferred.feedbackEmail ?? ""
                uiState.betaDescription = preferred.description ?? ""
            }
        } catch {
            uiState.error = error.localizedDescription
            Log.print.error("[BetaAppReviewInfo] Load failed: \(error.localizedDescription)")
        }

        uiState.isLoading = false
    }

    func save() async {
        uiState.didAttemptSave = true

        if uiState.hasValidationErrors {
            return
        }

        uiState.isSaving = true
        uiState.error = nil

        guard let connection = createConnection() else {
            uiState.isSaving = false
            return
        }

        do {
            if let detailId = uiState.reviewDetailId {
                let model = BetaAppReviewDetailModel(
                    id: detailId,
                    contactFirstName: uiState.contactFirstName,
                    contactLastName: uiState.contactLastName,
                    contactEmail: uiState.contactEmail,
                    contactPhone: uiState.contactPhone,
                    demoAccountName: uiState.demoAccountName,
                    demoAccountPassword: uiState.demoAccountPassword,
                    isDemoAccountRequired: uiState.isDemoAccountRequired
                )
                try await connection.updateBetaAppReviewDetail(model: model)
            }

            if let localizationId = uiState.localizationId {
                try await connection.updateBetaAppLocalization(
                    id: localizationId,
                    feedbackEmail: uiState.feedbackEmail,
                    description: uiState.betaDescription
                )
            } else {
                let created = try await connection.createBetaAppLocalization(
                    appId: uiState.appId,
                    locale: uiState.locale,
                    feedbackEmail: uiState.feedbackEmail,
                    description: uiState.betaDescription
                )
                uiState.localizationId = created.id
            }

            uiState.didSave = true
            Log.print.info("[BetaAppReviewInfo] Saved test information")
        } catch {
            uiState.error = error.localizedDescription
            Log.print.error("[BetaAppReviewInfo] Save failed: \(error.localizedDescription)")
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

// MARK: - Completeness Helper

struct BetaAppReviewInfoCompleteness {
    /// Returns true when the minimum fields Apple requires for a TestFlight beta submission
    /// are populated: Beta App Description, Feedback Email and full Contact Information.
    static func isComplete(detail: BetaAppReviewDetailModel?, localization: BetaAppLocalizationModel?) -> Bool {
        guard let detail else { return false }
        guard !(detail.contactFirstName ?? "").trimmingCharacters(in: .whitespaces).isEmpty,
              !(detail.contactLastName ?? "").trimmingCharacters(in: .whitespaces).isEmpty,
              !(detail.contactEmail ?? "").trimmingCharacters(in: .whitespaces).isEmpty,
              !(detail.contactPhone ?? "").trimmingCharacters(in: .whitespaces).isEmpty
        else { return false }

        if detail.isDemoAccountRequired == true {
            guard !(detail.demoAccountName ?? "").trimmingCharacters(in: .whitespaces).isEmpty,
                  !(detail.demoAccountPassword ?? "").trimmingCharacters(in: .whitespaces).isEmpty
            else { return false }
        }

        guard let localization else { return false }
        guard !(localization.description ?? "").trimmingCharacters(in: .whitespaces).isEmpty,
              !(localization.feedbackEmail ?? "").trimmingCharacters(in: .whitespaces).isEmpty
        else { return false }

        return true
    }
}
