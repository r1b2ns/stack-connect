import Foundation

// MARK: - Protocol

@MainActor
protocol AgeRatingViewModelProtocol: ObservableObject {
    var uiState: AgeRatingUiState { get set }
    func save() async
}

// MARK: - UiState

struct AgeRatingUiState {
    var account: AccountModel
    var declaration: AgeRatingDeclarationModel
    var isSaving = false
    var error: String?
    var toastMessage: ToastMessage?

    // Editable fields (level-based)
    var alcoholTobacco: AgeRatingLevel = .none
    var contests: AgeRatingLevel = .none
    var gamblingSimulated: AgeRatingLevel = .none
    var gunsOrOtherWeapons: AgeRatingLevel = .none
    var medicalInformation: AgeRatingLevel = .none
    var profanity: AgeRatingLevel = .none
    var sexualContentGraphic: AgeRatingLevel = .none
    var sexualContentOrNudity: AgeRatingLevel = .none
    var horrorOrFear: AgeRatingLevel = .none
    var matureOrSuggestive: AgeRatingLevel = .none
    var violenceCartoon: AgeRatingLevel = .none
    var violenceRealistic: AgeRatingLevel = .none
    var violenceGraphic: AgeRatingLevel = .none

    // Bool fields
    var isAdvertising = false
    var isGambling = false
    var isUnrestrictedWebAccess = false
    var isUserGeneratedContent = false

    // Override
    var ageRatingOverride: AgeRatingOverrideV2 = .none
}

// MARK: - Implementation

@MainActor
final class AgeRatingViewModel: AgeRatingViewModelProtocol {

    @Published var uiState: AgeRatingUiState

    private let keychain: KeyStorable

    init(
        ageRating: AgeRatingDeclarationModel,
        account: AccountModel,
        keychain: KeyStorable = KeychainStorable.shared
    ) {
        self.uiState = AgeRatingUiState(account: account, declaration: ageRating)
        self.keychain = keychain
        populateFields(from: ageRating)
    }

    func save() async {
        uiState.isSaving = true
        uiState.error = nil

        guard let connection = createConnection() else {
            uiState.isSaving = false
            return
        }

        do {
            try await connection.updateAgeRating(
                id: uiState.declaration.id,
                alcoholTobacco: uiState.alcoholTobacco.rawValue,
                contests: uiState.contests.rawValue,
                gamblingSimulated: uiState.gamblingSimulated.rawValue,
                gunsOrOtherWeapons: uiState.gunsOrOtherWeapons.rawValue,
                medicalInformation: uiState.medicalInformation.rawValue,
                profanity: uiState.profanity.rawValue,
                sexualContentGraphic: uiState.sexualContentGraphic.rawValue,
                sexualContentOrNudity: uiState.sexualContentOrNudity.rawValue,
                horrorOrFear: uiState.horrorOrFear.rawValue,
                matureOrSuggestive: uiState.matureOrSuggestive.rawValue,
                violenceCartoon: uiState.violenceCartoon.rawValue,
                violenceRealistic: uiState.violenceRealistic.rawValue,
                violenceGraphic: uiState.violenceGraphic.rawValue,
                isAdvertising: uiState.isAdvertising,
                isGambling: uiState.isGambling,
                isUnrestrictedWebAccess: uiState.isUnrestrictedWebAccess,
                isUserGeneratedContent: uiState.isUserGeneratedContent,
                ageRatingOverride: uiState.ageRatingOverride.rawValue
            )
            uiState.toastMessage = ToastMessage(String(localized: "Age rating updated"), icon: "checkmark.circle.fill")
            Log.print.info("[AgeRating] Saved")
        } catch {
            uiState.error = error.localizedDescription
            Log.print.error("[AgeRating] Save failed: \(error.localizedDescription)")
        }

        uiState.isSaving = false
    }

    // MARK: - Private

    private func populateFields(from d: AgeRatingDeclarationModel) {
        uiState.alcoholTobacco     = AgeRatingLevel(rawValue: d.alcoholTobaccoOrDrugUseOrReferences ?? "NONE") ?? .none
        uiState.contests           = AgeRatingLevel(rawValue: d.contests ?? "NONE") ?? .none
        uiState.gamblingSimulated  = AgeRatingLevel(rawValue: d.gamblingSimulated ?? "NONE") ?? .none
        uiState.gunsOrOtherWeapons = AgeRatingLevel(rawValue: d.gunsOrOtherWeapons ?? "NONE") ?? .none
        uiState.medicalInformation = AgeRatingLevel(rawValue: d.medicalOrTreatmentInformation ?? "NONE") ?? .none
        uiState.profanity          = AgeRatingLevel(rawValue: d.profanityOrCrudeHumor ?? "NONE") ?? .none
        uiState.sexualContentGraphic   = AgeRatingLevel(rawValue: d.sexualContentGraphicAndNudity ?? "NONE") ?? .none
        uiState.sexualContentOrNudity  = AgeRatingLevel(rawValue: d.sexualContentOrNudity ?? "NONE") ?? .none
        uiState.horrorOrFear       = AgeRatingLevel(rawValue: d.horrorOrFearThemes ?? "NONE") ?? .none
        uiState.matureOrSuggestive = AgeRatingLevel(rawValue: d.matureOrSuggestiveThemes ?? "NONE") ?? .none
        uiState.violenceCartoon    = AgeRatingLevel(rawValue: d.violenceCartoonOrFantasy ?? "NONE") ?? .none
        uiState.violenceRealistic  = AgeRatingLevel(rawValue: d.violenceRealistic ?? "NONE") ?? .none
        uiState.violenceGraphic    = AgeRatingLevel(rawValue: d.violenceRealisticProlongedGraphicOrSadistic ?? "NONE") ?? .none
        uiState.isAdvertising              = d.isAdvertising ?? false
        uiState.isGambling                 = d.isGambling ?? false
        uiState.isUnrestrictedWebAccess    = d.isUnrestrictedWebAccess ?? false
        uiState.isUserGeneratedContent     = d.isUserGeneratedContent ?? false
        uiState.ageRatingOverride = AgeRatingOverrideV2(rawValue: d.ageRatingOverrideV2 ?? "NONE") ?? .none
    }

    private func createConnection() -> AppleAccountConnection? {
        guard let credentials: AppleCredentials = keychain.object(forKey: "credentials.\(uiState.account.id)") else {
            return nil
        }
        return AppleAccountConnection(credentials: credentials)
    }
}
