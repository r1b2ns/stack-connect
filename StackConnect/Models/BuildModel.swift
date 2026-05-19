import Foundation

struct BuildModel: Codable, Identifiable, Hashable {
    let id: String
    var version: String?
    var processingState: String?
    var uploadedDate: Date?
    var iconUrl: String?
    var platform: String?
    var externalBuildState: String?
    var betaReviewState: String?
    var submittedDate: Date?

    init(
        id: String,
        version: String? = nil,
        processingState: String? = nil,
        uploadedDate: Date? = nil,
        iconUrl: String? = nil,
        platform: String? = nil,
        externalBuildState: String? = nil,
        betaReviewState: String? = nil,
        submittedDate: Date? = nil
    ) {
        self.id = id
        self.version = version
        self.processingState = processingState
        self.uploadedDate = uploadedDate
        self.iconUrl = iconUrl
        self.platform = platform
        self.externalBuildState = externalBuildState
        self.betaReviewState = betaReviewState
        self.submittedDate = submittedDate
    }

    /// True when the build can be submitted to Apple for external beta review.
    var canSubmitForBetaReview: Bool {
        externalBuildState == "READY_FOR_BETA_SUBMISSION"
    }

    /// True when the build is currently in (or waiting for) Apple's beta review.
    var isInBetaReview: Bool {
        externalBuildState == "WAITING_FOR_BETA_REVIEW" || externalBuildState == "IN_BETA_REVIEW"
    }
}

struct BetaBuildLocalizationModel: Codable, Identifiable, Hashable {
    let id: String
    var locale: String
    var whatsNew: String?
}
