#if DEBUG
import Foundation
import StackCoreRust

/// Everything one fake App Store Connect team holds, in the core's wire shapes
/// (`StackCoreRust` records), so the app's mapping code runs unchanged.
struct FakeAppStoreConnectState {

    /// Analytics segment → what to generate when it is downloaded.
    struct SegmentSource: Hashable {
        let appName: String
        let reportName: String
        let granularity: String
        let processingDate: String
    }

    var apps: [AppInfo] = []
    var iconUrls: [String: String] = [:]                                  // appId
    var versions: [String: [AppStoreVersionInfo]] = [:]                   // appId
    var versionLocalizations: [String: [AppStoreLocalizationInfo]] = [:]  // versionId
    var screenshotSets: [String: [ScreenshotSetInfo]] = [:]               // localizationId
    var appReviewDetails: [String: AppReviewDetailInfo] = [:]             // versionId
    var phasedReleases: [String: PhasedReleaseInfo] = [:]                 // versionId
    var versionBuilds: [String: String] = [:]                             // versionId → buildId
    var builds: [String: [BuildInfo]] = [:]                               // appId
    var betaGroups: [String: [BetaGroupInfo]] = [:]                       // appId
    var groupTesters: [String: [BetaTesterInfo]] = [:]                    // groupId
    var groupBuildIds: [String: [String]] = [:]                           // groupId
    var betaBuildLocalizations: [String: [BetaBuildLocalizationInfo]] = [:] // buildId
    var betaAppLocalizations: [String: [BetaAppLocalizationInfo]] = [:]   // appId
    var betaAppReviewDetails: [String: BetaAppReviewDetailInfo] = [:]     // appId
    var reviews: [String: [CustomerReview]] = [:]                         // appId
    var submissions: [String: [ReviewSubmission]] = [:]                   // appId
    var appInfos: [String: AppInfoDetails] = [:]                          // appId
    var accessibility: [String: [AccessibilityDeclarationInfo]] = [:]     // appId
    var categories: [AppCategoryInfo] = []
    var users: [UserInfo] = []
    var userVisibleApps: [String: [String]] = [:]                         // userId → appIds
    var teamMembers: [TeamMemberInfo] = []
    var devices: [DeviceInfo] = []
    var certificates: [CertificateInfo] = []
    var profiles: [ProvisioningProfileInfo] = []
    var bundleIds: [BundleIdInfo] = []
    var bundleCapabilities: [String: [BundleIdCapabilityInfo]] = [:]      // bundleId record id
    var analyticsRequests: [String: [AnalyticsReportRequest]] = [:]       // appId
    var analyticsReports: [String: [AnalyticsReport]] = [:]               // requestId
    var analyticsInstances: [String: [AnalyticsReportInstance]] = [:]     // reportId
    var analyticsSegments: [String: [AnalyticsReportSegment]] = [:]       // instanceId
    var segmentSources: [String: SegmentSource] = [:]                     // segment url

    // MARK: - Lookups

    func appId(forVersion versionId: String) -> String? {
        versions.first { $0.value.contains { $0.id == versionId } }?.key
    }

    func version(_ versionId: String) -> AppStoreVersionInfo? {
        versions.values.lazy.flatMap { $0 }.first { $0.id == versionId }
    }

    func app(_ appId: String) -> AppInfo? {
        apps.first { $0.id == appId }
    }

    func build(_ buildId: String) -> BuildInfo? {
        builds.values.lazy.flatMap { $0 }.first { $0.id == buildId }
    }

    func appId(forGroup groupId: String) -> String? {
        betaGroups.first { $0.value.contains { $0.id == groupId } }?.key
    }

    func localization(_ localizationId: String) -> AppStoreLocalizationInfo? {
        versionLocalizations.values.lazy.flatMap { $0 }.first { $0.id == localizationId }
    }

    // MARK: - Mutations

    mutating func updateVersion(_ versionId: String, _ change: (inout AppStoreVersionInfo) -> Void) throws {
        guard let appId = appId(forVersion: versionId),
              let index = versions[appId]?.firstIndex(where: { $0.id == versionId }) else {
            throw FakeCoreError.notFound("App Store version \(versionId)")
        }
        change(&versions[appId]![index])
    }

    mutating func updateBuild(_ buildId: String, _ change: (inout BuildInfo) -> Void) throws {
        for (appId, list) in builds {
            if let index = list.firstIndex(where: { $0.id == buildId }) {
                change(&builds[appId]![index])
                return
            }
        }
        throw FakeCoreError.notFound("Build \(buildId)")
    }

    mutating func updateGroup(_ groupId: String, _ change: (inout BetaGroupInfo) -> Void) throws {
        guard let appId = appId(forGroup: groupId),
              let index = betaGroups[appId]?.firstIndex(where: { $0.id == groupId }) else {
            throw FakeCoreError.notFound("Beta group \(groupId)")
        }
        change(&betaGroups[appId]![index])
    }

    /// The latest submission of `appId` in one of `states`, newest first.
    func openSubmissionIndex(appId: String, states: Set<String>) -> Int? {
        submissions[appId]?.indices
            .filter { states.contains(submissions[appId]![$0].state ?? "") }
            .max { (submissions[appId]![$0].submittedDate ?? "") < (submissions[appId]![$1].submittedDate ?? "") }
    }
}

/// One fake App Store Connect team (API key issuer).
final class FakeAppStoreConnectTeam: @unchecked Sendable {

    let issuerId: String
    let name: String
    let clock: FakeClock
    let state: FakeStateBox<FakeAppStoreConnectState>

    init(issuerId: String, name: String, clock: FakeClock, state: FakeAppStoreConnectState) {
        self.issuerId = issuerId
        self.name = name
        self.clock = clock
        self.state = FakeStateBox(state)
    }
}

/// Every fake App Store Connect team of the session, keyed by issuer ID.
/// Built once per launch from `FakeAppStoreConnectCatalog`; writes live in
/// memory until the app quits.
final class FakeAppStoreConnectBackend: @unchecked Sendable {

    private let lock = NSLock()
    private var teams: [String: FakeAppStoreConnectTeam]
    private let clock: FakeClock

    init(clock: FakeClock, teams: [FakeAppStoreConnectTeam]) {
        self.clock = clock
        self.teams = Dictionary(uniqueKeysWithValues: teams.map { ($0.issuerId, $0) })
    }

    /// The team for `issuerId`; an unknown issuer (an account added while in
    /// fake mode) gets an empty team.
    func team(issuerId: String) -> FakeAppStoreConnectTeam {
        lock.withLock {
            if let team = teams[issuerId] { return team }
            var empty = FakeAppStoreConnectState()
            empty.categories = FakeAppStoreConnectCatalog.categories
            let team = FakeAppStoreConnectTeam(issuerId: issuerId, name: "Sandbox", clock: clock, state: empty)
            teams[issuerId] = team
            return team
        }
    }
}
#endif
