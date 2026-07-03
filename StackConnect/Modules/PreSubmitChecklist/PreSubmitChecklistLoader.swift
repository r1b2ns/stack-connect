import Foundation

/// The App Store Connect reads needed to build a `PreSubmitChecklist`. Declared
/// as a focused protocol (rather than depending on the whole connection) so the
/// loader can be exercised with a mock in tests. `AppleAccountConnection`
/// already implements every method, so it conforms via an empty extension.
protocol PreSubmitChecklistDataSource: Sendable {
    func fetchCurrentBuild(versionId: String) async throws -> BuildModel?
    func fetchLocalizations(versionId: String) async throws -> [AppStoreLocalizationModel]
    func fetchAppReviewDetail(versionId: String) async throws -> AppReviewDetailModel?
    func fetchScreenshotSets(localizationId: String) async throws -> [ScreenshotSetModel]
    func fetchPhasedRelease(versionId: String) async throws -> PhasedReleaseModel?
}

extension AppleAccountConnection: PreSubmitChecklistDataSource {}

/// Orchestrates the parallel fetches that populate a `PreSubmitChecklist`.
///
/// Runs on the main actor because it's invoked from `@MainActor` view models and
/// the `Sendable` data source is safe to hand to the concurrent child fetches.
/// Individual fetch failures degrade gracefully to "missing" rather than
/// aborting the whole checklist — a failed fetch surfaces as an unmet
/// requirement, which is the safe default for a pre-submit gate.
@MainActor
enum PreSubmitChecklistLoader {

    static func load(
        source: any PreSubmitChecklistDataSource,
        version: AppStoreVersionModel
    ) async -> PreSubmitChecklist {
        async let buildTask = source.fetchCurrentBuild(versionId: version.id)
        async let localizationsTask = source.fetchLocalizations(versionId: version.id)
        async let reviewDetailTask = source.fetchAppReviewDetail(versionId: version.id)
        async let phasedTask = source.fetchPhasedRelease(versionId: version.id)

        let build = (try? await buildTask) ?? nil
        let localizations = (try? await localizationsTask) ?? []
        let reviewDetail = (try? await reviewDetailTask) ?? nil
        let phased = (try? await phasedTask) ?? nil

        let hasScreenshots = await Self.hasAnyScreenshot(
            source: source,
            localizations: localizations
        )

        return PreSubmitChecklist.make(
            version: version,
            build: build,
            localizations: localizations,
            reviewDetail: reviewDetail,
            phasedRelease: phased,
            hasScreenshots: hasScreenshots
        )
    }

    /// True as soon as any localization has at least one uploaded screenshot.
    private static func hasAnyScreenshot(
        source: any PreSubmitChecklistDataSource,
        localizations: [AppStoreLocalizationModel]
    ) async -> Bool {
        for localization in localizations {
            let sets = (try? await source.fetchScreenshotSets(localizationId: localization.id)) ?? []
            if sets.contains(where: { !$0.screenshots.isEmpty }) {
                return true
            }
        }
        return false
    }
}
