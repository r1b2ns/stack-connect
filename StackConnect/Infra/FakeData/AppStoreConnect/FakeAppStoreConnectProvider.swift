#if DEBUG
import Foundation
import StackCoreRust

/// In-memory App Store Connect provider: every capability the app uses, served
/// from one `FakeAppStoreConnectTeam`. Writes mutate the team's state, so they
/// succeed and show up on the next read (on any screen).
final class FakeAppStoreConnectProvider: FakeCoreProvider, @unchecked Sendable {

    private let team: FakeAppStoreConnectTeam

    init(team: FakeAppStoreConnectTeam) {
        self.team = team
        super.init(kind: .appStoreConnect)
    }

    required init(unsafeFromHandle handle: UInt64) {
        fatalError("Fake core providers are never lifted from the FFI")
    }

    override func capabilities() -> [Capability] {
        [.apps, .reviews, .appStoreVersions, .builds, .betaGroups, .betaBuildLocalizations,
         .betaAppLocalizations, .betaAppReviewDetail, .appMetadata, .accessibilityDeclarations,
         .users, .devices, .bundleIds, .certificates, .profiles, .analytics]
    }

    override func fetchApps() async throws -> [AppInfo] {
        team.state.read { $0.apps }
    }

    override func accessibilityDeclarations() -> AccessibilityDeclarations? { FakeASCAccessibilityDeclarations(team: team) }
    override func analytics() -> Analytics? { FakeASCAnalytics(team: team) }
    override func appMetadata() -> AppMetadata? { FakeASCAppMetadata(team: team) }
    override func appStoreVersions() -> AppStoreVersions? { FakeASCAppStoreVersions(team: team) }
    override func betaAppLocalizations() -> BetaAppLocalizations? { FakeASCBetaAppLocalizations(team: team) }
    override func betaAppReviewDetail() -> BetaAppReviewDetail? { FakeASCBetaAppReviewDetail(team: team) }
    override func betaBuildLocalizations() -> BetaBuildLocalizations? { FakeASCBetaBuildLocalizations(team: team) }
    override func betaGroups() -> BetaGroups? { FakeASCBetaGroups(team: team) }
    override func builds() -> Builds? { FakeASCBuilds(team: team) }
    override func bundleIds() -> BundleIds? { FakeASCBundleIds(team: team) }
    override func certificates() -> Certificates? { FakeASCCertificates(team: team) }
    override func devices() -> Devices? { FakeASCDevices(team: team) }
    override func profiles() -> Profiles? { FakeASCProfiles(team: team) }
    override func reviews() -> Reviews? { FakeASCReviews(team: team) }
    override func users() -> Users? { FakeASCUsers(team: team) }
}

// MARK: - App Store Versions

final class FakeASCAppStoreVersions: AppStoreVersions, @unchecked Sendable {

    private let team: FakeAppStoreConnectTeam
    private var state: FakeStateBox<FakeAppStoreConnectState> { team.state }

    init(team: FakeAppStoreConnectTeam) {
        self.team = team
        super.init(noHandle: .init())
    }

    required init(unsafeFromHandle handle: UInt64) {
        fatalError("Fake capabilities are never lifted from the FFI")
    }

    override func fetchVersions(appId: String, limit: UInt32) async throws -> [AppStoreVersionInfo] {
        state.read { state in
            let sorted = (state.versions[appId] ?? []).sorted { ($0.createdDate ?? "") > ($1.createdDate ?? "") }
            return Array(sorted.prefix(Int(limit)))
        }
    }

    override func createVersion(appId: String, platform: String, versionString: String) async throws -> AppStoreVersionInfo {
        let created = AppStoreVersionInfo(
            id: FakeID.make("ver"), appId: appId, platform: platform,
            appStoreState: "PREPARE_FOR_SUBMISSION", appVersionState: "PREPARE_FOR_SUBMISSION",
            versionString: versionString, copyright: "© \(Calendar.current.component(.year, from: team.clock.now)) \(team.name)",
            releaseType: "AFTER_APPROVAL", createdDate: FakeClock.iso(Date())
        )
        try state.write { state in
            guard state.app(appId) != nil else { throw FakeCoreError.notFound("App \(appId)") }
            state.versions[appId, default: []].append(created)
            // A new version starts from the previous version's metadata, as in ASC.
            let previous = (state.versions[appId] ?? [])
                .filter { $0.platform == platform && $0.id != created.id }
                .max { ($0.createdDate ?? "") < ($1.createdDate ?? "") }
            let copied = (previous.flatMap { state.versionLocalizations[$0.id] } ?? []).map { localization in
                AppStoreLocalizationInfo(
                    id: FakeID.make("loc"), locale: localization.locale, description: localization.description,
                    keywords: localization.keywords, promotionalText: localization.promotionalText,
                    supportUrl: localization.supportUrl, marketingUrl: localization.marketingUrl, whatsNew: nil
                )
            }
            state.versionLocalizations[created.id] = copied
            if let previousDetail = previous.flatMap({ state.appReviewDetails[$0.id] }) {
                var detail = previousDetail
                detail.id = FakeID.make("ard")
                state.appReviewDetails[created.id] = detail
            }
        }
        return created
    }

    override func updateVersion(id: String, versionString: String?, copyright: String?, releaseType: String?, earliestReleaseDate: String?) async throws {
        try state.write { state in
            try state.updateVersion(id) { version in
                if let versionString { version.versionString = versionString }
                if let copyright { version.copyright = copyright }
                if let releaseType { version.releaseType = releaseType }
            }
        }
    }

    override func deleteVersion(id: String) async throws {
        try state.write { state in
            guard let appId = state.appId(forVersion: id) else { throw FakeCoreError.notFound("App Store version \(id)") }
            state.versions[appId]?.removeAll { $0.id == id }
            state.versionLocalizations[id] = nil
            state.appReviewDetails[id] = nil
            state.phasedReleases[id] = nil
            state.versionBuilds[id] = nil
        }
    }

    override func submitForReview(appId: String, versionId: String, platform: String?) async throws {
        try state.write { state in
            guard let version = state.version(versionId) else { throw FakeCoreError.notFound("App Store version \(versionId)") }
            try state.updateVersion(versionId) {
                $0.appStoreState = "WAITING_FOR_REVIEW"
                $0.appVersionState = "WAITING_FOR_REVIEW"
            }
            let submission = ReviewSubmission(
                id: FakeID.make("sub"), appId: appId, platform: platform ?? version.platform,
                submittedDate: FakeClock.iso(Date()), state: "WAITING_FOR_REVIEW",
                versionString: version.versionString, versionId: versionId,
                submittedByName: FakeAppStoreConnectCatalog.apiKeyUserName, submittedByEmail: nil
            )
            state.submissions[appId, default: []].append(submission)
        }
    }

    override func cancelSubmission(appId: String) async throws {
        try cancel(appId: appId)
    }

    override func cancelReview(appId: String) async throws {
        try cancel(appId: appId)
    }

    /// Removes the app's version from review: the submission is cancelled and
    /// the version goes back to "Developer Rejected" (ASC's state after a cancel).
    private func cancel(appId: String) throws {
        try state.write { state in
            let open: Set<String> = ["READY_FOR_REVIEW", "WAITING_FOR_REVIEW", "IN_REVIEW"]
            guard let index = state.openSubmissionIndex(appId: appId, states: open) else {
                throw FakeCoreError.invalid("There is no submission in review for this app.")
            }
            state.submissions[appId]![index].state = "COMPLETE"
            if let versionId = state.submissions[appId]![index].versionId {
                try state.updateVersion(versionId) {
                    $0.appStoreState = "DEVELOPER_REJECTED"
                    $0.appVersionState = "DEVELOPER_REJECTED"
                }
            }
        }
    }

    override func rejectVersion(versionId: String) async throws {
        try state.write { state in
            try state.updateVersion(versionId) {
                $0.appStoreState = "DEVELOPER_REJECTED"
                $0.appVersionState = "DEVELOPER_REJECTED"
            }
        }
    }

    override func releaseVersion(versionId: String) async throws {
        try state.write { state in
            guard let appId = state.appId(forVersion: versionId), let released = state.version(versionId) else {
                throw FakeCoreError.notFound("App Store version \(versionId)")
            }
            // The live version of the same platform is replaced by the new one.
            for index in state.versions[appId]!.indices {
                let version = state.versions[appId]![index]
                if version.platform == released.platform, version.appStoreState == "READY_FOR_SALE", version.id != versionId {
                    state.versions[appId]![index].appStoreState = "REPLACED_WITH_NEW_VERSION"
                    state.versions[appId]![index].appVersionState = "REPLACED_WITH_NEW_VERSION"
                }
            }
            try state.updateVersion(versionId) {
                $0.appStoreState = "READY_FOR_SALE"
                $0.appVersionState = "READY_FOR_DISTRIBUTION"
            }
        }
    }

    override func fetchLocalizations(versionId: String) async throws -> [AppStoreLocalizationInfo] {
        state.read { $0.versionLocalizations[versionId] ?? [] }
    }

    override func updateLocalization(id: String, description: String?, keywords: String?, promotionalText: String?, supportUrl: String?, marketingUrl: String?, whatsNew: String?) async throws {
        try state.write { state in
            for (versionId, list) in state.versionLocalizations {
                guard let index = list.firstIndex(where: { $0.id == id }) else { continue }
                var localization = list[index]
                if let description { localization.description = description }
                if let keywords { localization.keywords = keywords }
                if let promotionalText { localization.promotionalText = promotionalText }
                if let supportUrl { localization.supportUrl = supportUrl }
                if let marketingUrl { localization.marketingUrl = marketingUrl }
                if let whatsNew { localization.whatsNew = whatsNew }
                state.versionLocalizations[versionId]![index] = localization
                return
            }
            throw FakeCoreError.notFound("Localization \(id)")
        }
    }

    override func fetchScreenshotSets(localizationId: String) async throws -> [ScreenshotSetInfo] {
        state.read { $0.screenshotSets[localizationId] ?? [] }
    }

    override func createScreenshotSet(localizationId: String, displayType: String) async throws -> ScreenshotSetInfo {
        let set = ScreenshotSetInfo(id: FakeID.make("sset"), displayType: displayType, screenshots: [])
        state.write { $0.screenshotSets[localizationId, default: []].append(set) }
        return set
    }

    override func deleteScreenshotSet(screenshotSetId: String) async throws {
        state.write { state in
            for key in state.screenshotSets.keys {
                state.screenshotSets[key]?.removeAll { $0.id == screenshotSetId }
            }
        }
    }

    override func uploadScreenshot(screenshotSetId: String, fileName: String, fileData: Data) async throws -> ScreenshotInfo {
        let size = FakeASCImageSize.pixelSize(of: fileData)
        let screenshot = ScreenshotInfo(
            id: FakeID.make("shot"),
            imageUrl: FakeMedia.screenshotURL(appName: "Upload", symbol: "photo.fill", color: "5B6B7F",
                                              caption: fileName, width: size.width, height: size.height),
            fileName: fileName, fileSize: Int32(clamping: fileData.count),
            width: Int32(size.width), height: Int32(size.height)
        )
        try state.write { state in
            for (key, sets) in state.screenshotSets {
                if let index = sets.firstIndex(where: { $0.id == screenshotSetId }) {
                    state.screenshotSets[key]![index].screenshots.append(screenshot)
                    return
                }
            }
            throw FakeCoreError.notFound("Screenshot set \(screenshotSetId)")
        }
        return screenshot
    }

    override func deleteScreenshot(screenshotId: String) async throws {
        state.write { state in
            for (key, sets) in state.screenshotSets {
                for index in sets.indices {
                    state.screenshotSets[key]![index].screenshots.removeAll { $0.id == screenshotId }
                }
            }
        }
    }

    override func fetchAppReviewDetail(versionId: String) async throws -> AppReviewDetailInfo? {
        state.read { $0.appReviewDetails[versionId] }
    }

    override func updateAppReviewDetail(detailId: String, contactFirstName: String?, contactLastName: String?, contactEmail: String?, contactPhone: String?, notes: String?, demoAccountName: String?, demoAccountPassword: String?, isDemoAccountRequired: Bool?) async throws -> AppReviewDetailInfo {
        try state.write { state in
            guard let versionId = state.appReviewDetails.first(where: { $0.value.id == detailId })?.key,
                  var detail = state.appReviewDetails[versionId] else {
                throw FakeCoreError.notFound("App review detail \(detailId)")
            }
            if let contactFirstName { detail.contactFirstName = contactFirstName }
            if let contactLastName { detail.contactLastName = contactLastName }
            if let contactEmail { detail.contactEmail = contactEmail }
            if let contactPhone { detail.contactPhone = contactPhone }
            if let notes { detail.notes = notes }
            if let demoAccountName { detail.demoAccountName = demoAccountName }
            if let demoAccountPassword { detail.demoAccountPassword = demoAccountPassword }
            if let isDemoAccountRequired { detail.isDemoAccountRequired = isDemoAccountRequired }
            state.appReviewDetails[versionId] = detail
            return detail
        }
    }

    override func fetchPhasedRelease(versionId: String) async throws -> PhasedReleaseInfo? {
        state.read { $0.phasedReleases[versionId] }
    }

    override func createPhasedRelease(versionId: String, state phasedState: String) async throws -> PhasedReleaseInfo {
        let phased = PhasedReleaseInfo(
            id: FakeID.make("phased"), state: phasedState,
            startDate: phasedState == "ACTIVE" ? FakeClock.iso(Date()) : nil,
            totalPauseDuration: 0, currentDayNumber: phasedState == "ACTIVE" ? 1 : 0
        )
        state.write { $0.phasedReleases[versionId] = phased }
        return phased
    }

    override func updatePhasedReleaseState(id: String, state phasedState: String) async throws -> PhasedReleaseInfo {
        try state.write { state in
            guard let versionId = state.phasedReleases.first(where: { $0.value.id == id })?.key,
                  var phased = state.phasedReleases[versionId] else {
                throw FakeCoreError.notFound("Phased release \(id)")
            }
            phased.state = phasedState
            if phasedState == "COMPLETE" { phased.currentDayNumber = 7 }
            if phasedState == "PAUSED" { phased.totalPauseDuration = (phased.totalPauseDuration ?? 0) }
            state.phasedReleases[versionId] = phased
            return phased
        }
    }

    override func deletePhasedRelease(id: String) async throws {
        state.write { state in
            if let versionId = state.phasedReleases.first(where: { $0.value.id == id })?.key {
                state.phasedReleases[versionId] = nil
            }
        }
    }
}

/// Reads a PNG / JPEG's pixel size from its header (enough for uploaded
/// screenshots; falls back to an iPhone 6.7" size).
enum FakeASCImageSize {
    static func pixelSize(of data: Data) -> (width: Int, height: Int) {
        let bytes = [UInt8](data.prefix(32))
        if bytes.count >= 24, bytes[0] == 0x89, bytes[1] == 0x50 {
            let width = Int(bytes[16]) << 24 | Int(bytes[17]) << 16 | Int(bytes[18]) << 8 | Int(bytes[19])
            let height = Int(bytes[20]) << 24 | Int(bytes[21]) << 16 | Int(bytes[22]) << 8 | Int(bytes[23])
            if width > 0, height > 0 { return (width, height) }
        }
        return (1290, 2796)
    }
}

// MARK: - Builds

final class FakeASCBuilds: Builds, @unchecked Sendable {

    private let team: FakeAppStoreConnectTeam
    private var state: FakeStateBox<FakeAppStoreConnectState> { team.state }

    init(team: FakeAppStoreConnectTeam) {
        self.team = team
        super.init(noHandle: .init())
    }

    required init(unsafeFromHandle handle: UInt64) {
        fatalError("Fake capabilities are never lifted from the FFI")
    }

    private static func newestFirst(_ builds: [BuildInfo]) -> [BuildInfo] {
        builds.sorted { ($0.uploadedDate ?? "") > ($1.uploadedDate ?? "") }
    }

    override func fetchBuilds(appId: String, limit: UInt32) async throws -> [BuildInfo] {
        state.read { Array(Self.newestFirst($0.builds[appId] ?? []).prefix(Int(limit))) }
    }

    override func fetchBuildsPage(appId: String, platform: String?, processingStates: [String], limit: UInt32, pageToken: String?) async throws -> BuildsPage {
        let all = state.read { state in
            Self.newestFirst(state.builds[appId] ?? []).filter { build in
                (platform == nil || build.platform == platform)
                    && (processingStates.isEmpty || processingStates.contains(build.processingState ?? ""))
            }
        }
        let offset = pageToken.flatMap(Int.init) ?? 0
        let page = Array(all.dropFirst(offset).prefix(Int(max(limit, 1))))
        let next = offset + page.count < all.count ? String(offset + page.count) : nil
        return BuildsPage(builds: page, nextToken: next)
    }

    override func fetchBuildsForGroup(groupId: String, limit: UInt32) async throws -> [BuildInfo] {
        state.read { state in
            let ids = state.groupBuildIds[groupId] ?? []
            return Array(Self.newestFirst(ids.compactMap { state.build($0) }).prefix(Int(limit)))
        }
    }

    override func fetchBuildDetail(buildId: String) async throws -> BuildDetailInfo {
        try state.read { state in
            guard let build = state.build(buildId) else { throw FakeCoreError.notFound("Build \(buildId)") }
            let groups = (state.betaGroups[build.appId] ?? []).filter { group in
                (state.groupBuildIds[group.id] ?? []).contains(buildId)
            }
            return BuildDetailInfo(build: build, betaGroups: groups, localizations: state.betaBuildLocalizations[buildId] ?? [])
        }
    }

    override func fetchCurrentBuild(versionId: String) async throws -> BuildInfo? {
        state.read { state in state.versionBuilds[versionId].flatMap { state.build($0) } }
    }

    override func attachBuild(versionId: String, buildId: String) async throws {
        try state.write { state in
            guard state.build(buildId) != nil else { throw FakeCoreError.notFound("Build \(buildId)") }
            state.versionBuilds[versionId] = buildId
        }
    }

    override func addBuildToGroups(buildId: String, groupIds: [String]) async throws {
        try state.write { state in
            for groupId in groupIds {
                var ids = state.groupBuildIds[groupId] ?? []
                if !ids.contains(buildId) { ids.append(buildId) }
                state.groupBuildIds[groupId] = ids
            }
            try state.updateBuild(buildId) { build in
                if build.externalBuildState == "READY_FOR_BETA_SUBMISSION" || build.externalBuildState == nil {
                    build.externalBuildState = "IN_BETA_TESTING"
                }
            }
        }
    }

    override func removeBuildFromGroup(buildId: String, groupId: String) async throws {
        state.write { $0.groupBuildIds[groupId]?.removeAll { $0 == buildId } }
    }

    override func expireBuild(buildId: String) async throws {
        try state.write { state in
            try state.updateBuild(buildId) { build in
                build.expired = true
                build.expirationDate = FakeClock.iso(Date())
                build.externalBuildState = "EXPIRED"
                build.internalBuildState = "EXPIRED"
            }
        }
    }

    override func submitBuildForBetaReview(buildId: String) async throws {
        try state.write { state in
            try state.updateBuild(buildId) { build in
                build.betaReviewState = "WAITING_FOR_REVIEW"
                build.externalBuildState = "WAITING_FOR_BETA_REVIEW"
                build.submittedDate = FakeClock.iso(Date())
            }
        }
    }
}

// MARK: - Beta Groups

final class FakeASCBetaGroups: BetaGroups, @unchecked Sendable {

    private let team: FakeAppStoreConnectTeam
    private var state: FakeStateBox<FakeAppStoreConnectState> { team.state }

    init(team: FakeAppStoreConnectTeam) {
        self.team = team
        super.init(noHandle: .init())
    }

    required init(unsafeFromHandle handle: UInt64) {
        fatalError("Fake capabilities are never lifted from the FFI")
    }

    override func fetchBetaGroups(appId: String, limit: UInt32) async throws -> [BetaGroupInfo] {
        state.read { Array(($0.betaGroups[appId] ?? []).prefix(Int(limit))) }
    }

    override func fetchBetaTesters(groupId: String, limit: UInt32) async throws -> [BetaTesterInfo] {
        state.read { Array(($0.groupTesters[groupId] ?? []).prefix(Int(limit))) }
    }

    override func fetchTesterCount(groupId: String) async throws -> UInt32 {
        state.read { UInt32($0.groupTesters[groupId]?.count ?? 0) }
    }

    override func createBetaGroup(appId: String, name: String, isInternal: Bool, publicLinkEnabled: Bool, hasAccessToAllBuilds: Bool) async throws -> BetaGroupInfo {
        let group = BetaGroupInfo(
            id: FakeID.make("group"), appId: appId, name: name, createdDate: FakeClock.iso(Date()),
            isInternalGroup: isInternal, hasAccessToAllBuilds: hasAccessToAllBuilds,
            publicLinkEnabled: publicLinkEnabled,
            publicLink: publicLinkEnabled ? "https://testflight.fakedata.example/join/\(UUID().uuidString.prefix(8))" : nil,
            feedbackEnabled: true
        )
        state.write { $0.betaGroups[appId, default: []].append(group) }
        return group
    }

    override func updateBetaGroup(groupId: String, name: String?, publicLinkEnabled: Bool?, publicLinkLimit: Int32?, feedbackEnabled: Bool?) async throws -> BetaGroupInfo {
        try state.write { state in
            try state.updateGroup(groupId) { group in
                if let name { group.name = name }
                if let publicLinkEnabled {
                    group.publicLinkEnabled = publicLinkEnabled
                    if publicLinkEnabled, group.publicLink == nil {
                        group.publicLink = "https://testflight.fakedata.example/join/\(UUID().uuidString.prefix(8))"
                    }
                }
                if let feedbackEnabled { group.feedbackEnabled = feedbackEnabled }
            }
            guard let appId = state.appId(forGroup: groupId),
                  let group = state.betaGroups[appId]?.first(where: { $0.id == groupId }) else {
                throw FakeCoreError.notFound("Beta group \(groupId)")
            }
            return group
        }
    }

    override func deleteBetaGroup(groupId: String) async throws {
        state.write { state in
            for key in state.betaGroups.keys {
                state.betaGroups[key]?.removeAll { $0.id == groupId }
            }
            state.groupTesters[groupId] = nil
            state.groupBuildIds[groupId] = nil
        }
    }

    override func addBetaTester(groupId: String, email: String, firstName: String?, lastName: String?) async throws -> BetaTesterInfo {
        let tester = BetaTesterInfo(id: FakeID.make("tester"), firstName: firstName, lastName: lastName, email: email, inviteType: "EMAIL", state: "INVITED")
        try state.write { state in
            guard state.appId(forGroup: groupId) != nil else { throw FakeCoreError.notFound("Beta group \(groupId)") }
            state.groupTesters[groupId, default: []].append(tester)
        }
        return tester
    }

    override func removeBetaTester(groupId: String, testerId: String) async throws {
        state.write { $0.groupTesters[groupId]?.removeAll { $0.id == testerId } }
    }

    override func resendInvite(testerId: String, appId: String) async throws {}
}

// MARK: - Beta localizations / review detail

final class FakeASCBetaBuildLocalizations: BetaBuildLocalizations, @unchecked Sendable {

    private let team: FakeAppStoreConnectTeam
    private var state: FakeStateBox<FakeAppStoreConnectState> { team.state }

    init(team: FakeAppStoreConnectTeam) {
        self.team = team
        super.init(noHandle: .init())
    }

    required init(unsafeFromHandle handle: UInt64) {
        fatalError("Fake capabilities are never lifted from the FFI")
    }

    override func fetchBetaBuildLocalizations(buildId: String, limit: UInt32) async throws -> [BetaBuildLocalizationInfo] {
        state.read { Array(($0.betaBuildLocalizations[buildId] ?? []).prefix(Int(limit))) }
    }

    override func createBetaBuildLocalization(buildId: String, locale: String, whatsNew: String) async throws -> BetaBuildLocalizationInfo {
        let localization = BetaBuildLocalizationInfo(id: FakeID.make("bbl"), locale: locale, whatsNew: whatsNew)
        state.write { $0.betaBuildLocalizations[buildId, default: []].append(localization) }
        return localization
    }

    override func updateBetaBuildLocalization(id: String, whatsNew: String) async throws -> BetaBuildLocalizationInfo {
        try state.write { state in
            for (buildId, list) in state.betaBuildLocalizations {
                if let index = list.firstIndex(where: { $0.id == id }) {
                    state.betaBuildLocalizations[buildId]![index].whatsNew = whatsNew
                    return state.betaBuildLocalizations[buildId]![index]
                }
            }
            throw FakeCoreError.notFound("Beta build localization \(id)")
        }
    }
}

final class FakeASCBetaAppLocalizations: BetaAppLocalizations, @unchecked Sendable {

    private let team: FakeAppStoreConnectTeam
    private var state: FakeStateBox<FakeAppStoreConnectState> { team.state }

    init(team: FakeAppStoreConnectTeam) {
        self.team = team
        super.init(noHandle: .init())
    }

    required init(unsafeFromHandle handle: UInt64) {
        fatalError("Fake capabilities are never lifted from the FFI")
    }

    override func fetchBetaAppLocalizations(appId: String, limit: UInt32) async throws -> [BetaAppLocalizationInfo] {
        state.read { Array(($0.betaAppLocalizations[appId] ?? []).prefix(Int(limit))) }
    }

    override func createBetaAppLocalization(appId: String, locale: String, feedbackEmail: String?, description: String?) async throws -> BetaAppLocalizationInfo {
        let localization = BetaAppLocalizationInfo(id: FakeID.make("bal"), locale: locale, feedbackEmail: feedbackEmail, description: description)
        state.write { $0.betaAppLocalizations[appId, default: []].append(localization) }
        return localization
    }

    override func updateBetaAppLocalization(id: String, feedbackEmail: String?, description: String?) async throws -> BetaAppLocalizationInfo {
        try state.write { state in
            for (appId, list) in state.betaAppLocalizations {
                if let index = list.firstIndex(where: { $0.id == id }) {
                    if let feedbackEmail { state.betaAppLocalizations[appId]![index].feedbackEmail = feedbackEmail }
                    if let description { state.betaAppLocalizations[appId]![index].description = description }
                    return state.betaAppLocalizations[appId]![index]
                }
            }
            throw FakeCoreError.notFound("Beta app localization \(id)")
        }
    }
}

final class FakeASCBetaAppReviewDetail: BetaAppReviewDetail, @unchecked Sendable {

    private let team: FakeAppStoreConnectTeam
    private var state: FakeStateBox<FakeAppStoreConnectState> { team.state }

    init(team: FakeAppStoreConnectTeam) {
        self.team = team
        super.init(noHandle: .init())
    }

    required init(unsafeFromHandle handle: UInt64) {
        fatalError("Fake capabilities are never lifted from the FFI")
    }

    override func fetchBetaAppReviewDetail(appId: String) async throws -> BetaAppReviewDetailInfo {
        try state.read { state in
            guard let detail = state.betaAppReviewDetails[appId] else { throw FakeCoreError.notFound("Beta app review detail for \(appId)") }
            return detail
        }
    }

    override func updateBetaAppReviewDetail(detailId: String, contactFirstName: String?, contactLastName: String?, contactEmail: String?, contactPhone: String?, demoAccountName: String?, demoAccountPassword: String?, isDemoAccountRequired: Bool?, notes: String?) async throws -> BetaAppReviewDetailInfo {
        try state.write { state in
            guard let appId = state.betaAppReviewDetails.first(where: { $0.value.id == detailId })?.key,
                  var detail = state.betaAppReviewDetails[appId] else {
                throw FakeCoreError.notFound("Beta app review detail \(detailId)")
            }
            if let contactFirstName { detail.contactFirstName = contactFirstName }
            if let contactLastName { detail.contactLastName = contactLastName }
            if let contactEmail { detail.contactEmail = contactEmail }
            if let contactPhone { detail.contactPhone = contactPhone }
            if let demoAccountName { detail.demoAccountName = demoAccountName }
            if let demoAccountPassword { detail.demoAccountPassword = demoAccountPassword }
            if let isDemoAccountRequired { detail.isDemoAccountRequired = isDemoAccountRequired }
            if let notes { detail.notes = notes }
            state.betaAppReviewDetails[appId] = detail
            return detail
        }
    }
}

// MARK: - Reviews

final class FakeASCReviews: Reviews, @unchecked Sendable {

    private let team: FakeAppStoreConnectTeam
    private var state: FakeStateBox<FakeAppStoreConnectState> { team.state }

    init(team: FakeAppStoreConnectTeam) {
        self.team = team
        super.init(noHandle: .init())
    }

    required init(unsafeFromHandle handle: UInt64) {
        fatalError("Fake capabilities are never lifted from the FFI")
    }

    override func fetchCustomerReviews(appId: String) async throws -> [CustomerReview] {
        state.read { ($0.reviews[appId] ?? []).sorted { ($0.createdDate ?? "") > ($1.createdDate ?? "") } }
    }

    override func fetchCustomerReviewsPage(appId: String, sort: String, filterRating: [String], limit: UInt32, pageToken: String?) async throws -> CustomerReviewsPage {
        let ratings = Set(filterRating.compactMap(Int32.init))
        let all = state.read { state -> [CustomerReview] in
            let filtered = (state.reviews[appId] ?? []).filter { ratings.isEmpty || ratings.contains($0.rating) }
            return FakeReviewPaging.sorted(filtered, by: sort)
        }
        return FakeReviewPaging.page(all, limit: limit, pageToken: pageToken)
    }

    override func replyToReview(reviewId: String, body: String) async throws -> ReviewResponse {
        let response = ReviewResponse(id: FakeID.make("resp"), body: body, state: "PENDING_PUBLISH", lastModifiedDate: FakeClock.iso(Date()))
        try state.write { state in
            for (appId, list) in state.reviews {
                if let index = list.firstIndex(where: { $0.id == reviewId }) {
                    state.reviews[appId]![index].response = response
                    return
                }
            }
            throw FakeCoreError.notFound("Customer review \(reviewId)")
        }
        return response
    }

    override func deleteReviewResponse(responseId: String) async throws {
        state.write { state in
            for (appId, list) in state.reviews {
                for index in list.indices where list[index].response?.id == responseId {
                    state.reviews[appId]![index].response = nil
                }
            }
        }
    }

    override func fetchReviewSubmissions(appId: String) async throws -> [ReviewSubmission] {
        state.read { ($0.submissions[appId] ?? []).sorted { ($0.submittedDate ?? "") > ($1.submittedDate ?? "") } }
    }

    override func submitReviewSubmission(submissionId: String) async throws {
        try state.write { state in
            for (appId, list) in state.submissions {
                if let index = list.firstIndex(where: { $0.id == submissionId }) {
                    state.submissions[appId]![index].state = "WAITING_FOR_REVIEW"
                    state.submissions[appId]![index].submittedDate = FakeClock.iso(Date())
                    if let versionId = list[index].versionId {
                        try state.updateVersion(versionId) {
                            $0.appStoreState = "WAITING_FOR_REVIEW"
                            $0.appVersionState = "WAITING_FOR_REVIEW"
                        }
                    }
                    return
                }
            }
            throw FakeCoreError.notFound("Review submission \(submissionId)")
        }
    }

    override func discardReviewSubmission(submissionId: String) async throws {
        state.write { state in
            for key in state.submissions.keys {
                state.submissions[key]?.removeAll { $0.id == submissionId && $0.state == "READY_FOR_REVIEW" }
            }
        }
    }
}

/// Sorting and offset paging of fake review lists, shared by both stores.
enum FakeReviewPaging {

    /// `sort` uses the App Store Connect values (`-createdDate`, `createdDate`,
    /// `-rating`, `rating`); anything else keeps newest first.
    static func sorted(_ reviews: [CustomerReview], by sort: String) -> [CustomerReview] {
        switch sort {
        case "createdDate": return reviews.sorted { ($0.createdDate ?? "") < ($1.createdDate ?? "") }
        case "-rating":     return reviews.sorted { ($0.rating, $0.createdDate ?? "") > ($1.rating, $1.createdDate ?? "") }
        case "rating":      return reviews.sorted { ($0.rating, $1.createdDate ?? "") < ($1.rating, $0.createdDate ?? "") }
        default:            return reviews.sorted { ($0.createdDate ?? "") > ($1.createdDate ?? "") }
        }
    }

    static func page(_ reviews: [CustomerReview], limit: UInt32, pageToken: String?) -> CustomerReviewsPage {
        let offset = pageToken.flatMap(Int.init) ?? 0
        let size = max(Int(limit), 1)
        let page = Array(reviews.dropFirst(offset).prefix(size))
        let next = offset + page.count < reviews.count ? String(offset + page.count) : nil
        return CustomerReviewsPage(reviews: page, nextToken: next)
    }
}

// MARK: - App metadata (app info, categories, age rating, privacy, icon)

final class FakeASCAppMetadata: AppMetadata, @unchecked Sendable {

    private let team: FakeAppStoreConnectTeam
    private var state: FakeStateBox<FakeAppStoreConnectState> { team.state }

    init(team: FakeAppStoreConnectTeam) {
        self.team = team
        super.init(noHandle: .init())
    }

    required init(unsafeFromHandle handle: UInt64) {
        fatalError("Fake capabilities are never lifted from the FFI")
    }

    override func fetchIconUrl(appId: String) async throws -> String? {
        state.read { $0.iconUrls[appId] }
    }

    override func fetchAppInfo(appId: String) async throws -> AppInfoDetails {
        try state.read { state in
            guard let info = state.appInfos[appId] else { throw FakeCoreError.notFound("App info for \(appId)") }
            return info
        }
    }

    override func fetchAppCategories() async throws -> [AppCategoryInfo] {
        state.read { $0.categories }
    }

    override func fetchAppInfoLocalizations(appInfoId: String) async throws -> [AppInfoLocalizationInfo] {
        state.read { state in state.appInfos.values.first { $0.appInfoId == appInfoId }?.localizations ?? [] }
    }

    override func createAppInfoLocalization(appInfoId: String, locale: String, name: String, subtitle: String?) async throws -> AppInfoLocalizationInfo {
        let localization = AppInfoLocalizationInfo(id: FakeID.make("ail"), locale: locale, name: name, subtitle: subtitle,
                                                   privacyPolicyUrl: nil, privacyChoicesUrl: nil, privacyPolicyText: nil)
        try updateInfo(appInfoId: appInfoId) { $0.localizations.append(localization) }
        return localization
    }

    override func deleteAppInfoLocalization(id: String) async throws {
        state.write { state in
            for key in state.appInfos.keys {
                state.appInfos[key]?.localizations.removeAll { $0.id == id }
            }
        }
    }

    override func updateAppInfoLocalization(id: String, name: String, subtitle: String?) async throws -> AppInfoLocalizationInfo {
        try updateLocalization(id: id) { localization in
            localization.name = name
            localization.subtitle = subtitle
        }
    }

    override func updateAppInfoLocalizationPrivacy(id: String, privacyPolicyUrl: String?, privacyChoicesUrl: String?, privacyPolicyText: String?) async throws -> AppInfoLocalizationInfo {
        try updateLocalization(id: id) { localization in
            localization.privacyPolicyUrl = privacyPolicyUrl
            localization.privacyChoicesUrl = privacyChoicesUrl
            localization.privacyPolicyText = privacyPolicyText
        }
    }

    override func updateAppInfoCategory(appInfoId: String, primaryCategoryId: String?, subcategoryOneId: String?, secondaryCategoryId: String?, secondarySubcategoryOneId: String?) async throws {
        try updateInfo(appInfoId: appInfoId) { info in
            info.primaryCategoryId = primaryCategoryId
            info.primarySubcategoryOneId = subcategoryOneId
            info.secondaryCategoryId = secondaryCategoryId
            info.secondarySubcategoryOneId = secondarySubcategoryOneId
        }
    }

    override func updateApp(id: String, contentRightsDeclaration: String?, primaryLocale: String?) async throws {
        try state.write { state in
            guard var info = state.appInfos[id] else { throw FakeCoreError.notFound("App \(id)") }
            if let contentRightsDeclaration { info.contentRightsDeclaration = contentRightsDeclaration }
            if let primaryLocale { info.primaryLocale = primaryLocale }
            state.appInfos[id] = info
        }
    }

    override func updateAgeRating(id: String, alcoholTobacco: String, contests: String, gamblingSimulated: String, gunsOrOtherWeapons: String, medicalInformation: String, profanity: String, sexualContentGraphic: String, sexualContentOrNudity: String, horrorOrFear: String, matureOrSuggestive: String, violenceCartoon: String, violenceRealistic: String, violenceGraphic: String, isAdvertising: Bool, isGambling: Bool, isUnrestrictedWebAccess: Bool, isUserGeneratedContent: Bool, ageRatingOverride: String) async throws {
        try state.write { state in
            guard let appId = state.appInfos.first(where: { $0.value.ageRatingDeclarationId == id })?.key else {
                throw FakeCoreError.notFound("Age rating declaration \(id)")
            }
            state.appInfos[appId]?.ageRating = AgeRatingDeclarationInfo(
                id: id,
                alcoholTobaccoOrDrugUseOrReferences: alcoholTobacco, contests: contests,
                gamblingSimulated: gamblingSimulated, gunsOrOtherWeapons: gunsOrOtherWeapons,
                medicalOrTreatmentInformation: medicalInformation, profanityOrCrudeHumor: profanity,
                sexualContentGraphicAndNudity: sexualContentGraphic, sexualContentOrNudity: sexualContentOrNudity,
                horrorOrFearThemes: horrorOrFear, matureOrSuggestiveThemes: matureOrSuggestive,
                violenceCartoonOrFantasy: violenceCartoon, violenceRealistic: violenceRealistic,
                violenceRealisticProlongedGraphicOrSadistic: violenceGraphic,
                isAdvertising: isAdvertising, isGambling: isGambling,
                isUnrestrictedWebAccess: isUnrestrictedWebAccess, isUserGeneratedContent: isUserGeneratedContent,
                ageRatingOverrideV2: ageRatingOverride
            )
        }
    }

    private func updateInfo(appInfoId: String, _ change: (inout AppInfoDetails) -> Void) throws {
        try state.write { state in
            guard let appId = state.appInfos.first(where: { $0.value.appInfoId == appInfoId })?.key else {
                throw FakeCoreError.notFound("App info \(appInfoId)")
            }
            change(&state.appInfos[appId]!)
        }
    }

    private func updateLocalization(id: String, _ change: (inout AppInfoLocalizationInfo) -> Void) throws -> AppInfoLocalizationInfo {
        try state.write { state in
            for (appId, info) in state.appInfos {
                if let index = info.localizations.firstIndex(where: { $0.id == id }) {
                    change(&state.appInfos[appId]!.localizations[index])
                    return state.appInfos[appId]!.localizations[index]
                }
            }
            throw FakeCoreError.notFound("App info localization \(id)")
        }
    }
}

// MARK: - Accessibility

final class FakeASCAccessibilityDeclarations: AccessibilityDeclarations, @unchecked Sendable {

    private let team: FakeAppStoreConnectTeam
    private var state: FakeStateBox<FakeAppStoreConnectState> { team.state }

    init(team: FakeAppStoreConnectTeam) {
        self.team = team
        super.init(noHandle: .init())
    }

    required init(unsafeFromHandle handle: UInt64) {
        fatalError("Fake capabilities are never lifted from the FFI")
    }

    override func fetchAccessibilityDeclarations(appId: String, limit: Int64) async throws -> [AccessibilityDeclarationInfo] {
        state.read { Array(($0.accessibility[appId] ?? []).prefix(Int(limit))) }
    }

    override func createAccessibilityDeclaration(appId: String, deviceFamily: String) async throws -> AccessibilityDeclarationInfo {
        let declaration = AccessibilityDeclarationInfo(
            id: FakeID.make("a11y"), deviceFamily: deviceFamily, state: "DRAFT",
            supportsAudioDescriptions: false, supportsCaptions: false, supportsDarkInterface: false,
            supportsDifferentiateWithoutColor: false, supportsLargerText: false, supportsReducedMotion: false,
            supportsSufficientContrast: false, supportsVoiceControl: false, supportsVoiceover: false
        )
        state.write { $0.accessibility[appId, default: []].append(declaration) }
        return declaration
    }

    override func updateAccessibilityDeclaration(id: String, publish: Bool, supportsAudioDescriptions: Bool, supportsCaptions: Bool, supportsDarkInterface: Bool, supportsDifferentiateWithoutColor: Bool, supportsLargerText: Bool, supportsReducedMotion: Bool, supportsSufficientContrast: Bool, supportsVoiceControl: Bool, supportsVoiceover: Bool) async throws -> AccessibilityDeclarationInfo {
        try state.write { state in
            for (appId, list) in state.accessibility {
                guard let index = list.firstIndex(where: { $0.id == id }) else { continue }
                var declaration = list[index]
                declaration.state = publish ? "PUBLISHED" : "DRAFT"
                declaration.supportsAudioDescriptions = supportsAudioDescriptions
                declaration.supportsCaptions = supportsCaptions
                declaration.supportsDarkInterface = supportsDarkInterface
                declaration.supportsDifferentiateWithoutColor = supportsDifferentiateWithoutColor
                declaration.supportsLargerText = supportsLargerText
                declaration.supportsReducedMotion = supportsReducedMotion
                declaration.supportsSufficientContrast = supportsSufficientContrast
                declaration.supportsVoiceControl = supportsVoiceControl
                declaration.supportsVoiceover = supportsVoiceover
                state.accessibility[appId]![index] = declaration
                return declaration
            }
            throw FakeCoreError.notFound("Accessibility declaration \(id)")
        }
    }

    override func deleteAccessibilityDeclaration(id: String) async throws {
        state.write { state in
            for key in state.accessibility.keys {
                state.accessibility[key]?.removeAll { $0.id == id }
            }
        }
    }
}

// MARK: - Users

final class FakeASCUsers: Users, @unchecked Sendable {

    private let team: FakeAppStoreConnectTeam
    private var state: FakeStateBox<FakeAppStoreConnectState> { team.state }

    init(team: FakeAppStoreConnectTeam) {
        self.team = team
        super.init(noHandle: .init())
    }

    required init(unsafeFromHandle handle: UInt64) {
        fatalError("Fake capabilities are never lifted from the FFI")
    }

    override func fetchUsers() async throws -> [UserInfo] {
        state.read { $0.users }
    }

    override func fetchTeamMembers() async throws -> [TeamMemberInfo] {
        state.read { $0.teamMembers }
    }

    override func fetchUserVisibleApps(id: String) async throws -> [String] {
        state.read { $0.userVisibleApps[id] ?? [] }
    }

    override func updateUserVisibleApps(id: String, appIds: [String]) async throws {
        state.write { $0.userVisibleApps[id] = appIds }
    }

    override func inviteUser(email: String, firstName: String, lastName: String, roles: [String], allAppsVisible: Bool, provisioningAllowed: Bool) async throws {
        try state.write { state in
            guard !state.users.contains(where: { $0.email?.lowercased() == email.lowercased() }) else {
                throw FakeCoreError.invalid("A user with this email address is already on the team.")
            }
            state.users.append(UserInfo(
                id: FakeID.make("invite"), firstName: firstName, lastName: lastName, email: email, roles: roles,
                allAppsVisible: allAppsVisible, provisioningAllowed: provisioningAllowed, isPending: true,
                expirationDate: FakeClock.iso(Date().addingTimeInterval(30 * 86_400))
            ))
        }
    }

    override func updateUser(id: String, roles: [String], allAppsVisible: Bool, provisioningAllowed: Bool) async throws {
        try state.write { state in
            guard let index = state.users.firstIndex(where: { $0.id == id }) else { throw FakeCoreError.notFound("User \(id)") }
            state.users[index].roles = roles
            state.users[index].allAppsVisible = allAppsVisible
            state.users[index].provisioningAllowed = provisioningAllowed
        }
    }

    override func deleteUser(id: String, isPending: Bool) async throws {
        state.write { state in
            state.users.removeAll { $0.id == id }
            state.userVisibleApps[id] = nil
        }
    }
}

// MARK: - Provisioning: devices, bundle IDs, certificates, profiles

final class FakeASCDevices: Devices, @unchecked Sendable {

    private let team: FakeAppStoreConnectTeam
    private var state: FakeStateBox<FakeAppStoreConnectState> { team.state }

    init(team: FakeAppStoreConnectTeam) {
        self.team = team
        super.init(noHandle: .init())
    }

    required init(unsafeFromHandle handle: UInt64) {
        fatalError("Fake capabilities are never lifted from the FFI")
    }

    override func fetchDevices() async throws -> [DeviceInfo] {
        state.read { $0.devices }
    }

    override func createDevice(name: String, platform: String, udid: String) async throws -> DeviceInfo {
        let device = DeviceInfo(id: FakeID.make("device"), name: name, udid: udid, platform: platform,
                                deviceClass: platform == "MAC_OS" ? "MAC" : "IPHONE", model: nil,
                                status: "ENABLED", addedDate: FakeClock.iso(Date()))
        try state.write { state in
            guard !state.devices.contains(where: { $0.udid == udid }) else {
                throw FakeCoreError.invalid("A device with this UDID is already registered.")
            }
            state.devices.append(device)
        }
        return device
    }

    override func updateDevice(id: String, name: String?, status: String?) async throws {
        try state.write { state in
            guard let index = state.devices.firstIndex(where: { $0.id == id }) else { throw FakeCoreError.notFound("Device \(id)") }
            if let name { state.devices[index].name = name }
            if let status { state.devices[index].status = status }
        }
    }
}

final class FakeASCBundleIds: BundleIds, @unchecked Sendable {

    private let team: FakeAppStoreConnectTeam
    private var state: FakeStateBox<FakeAppStoreConnectState> { team.state }

    init(team: FakeAppStoreConnectTeam) {
        self.team = team
        super.init(noHandle: .init())
    }

    required init(unsafeFromHandle handle: UInt64) {
        fatalError("Fake capabilities are never lifted from the FFI")
    }

    override func fetchBundleIds() async throws -> [BundleIdInfo] {
        state.read { $0.bundleIds }
    }

    override func createBundleId(identifier: String, name: String, platform: String) async throws -> BundleIdInfo {
        try state.write { state in
            guard !state.bundleIds.contains(where: { $0.identifier == identifier }) else {
                throw FakeCoreError.invalid("An App ID with Identifier '\(identifier)' is not available.")
            }
            let bundle = BundleIdInfo(id: FakeID.make("bundle"), identifier: identifier, name: name, platform: platform,
                                      seedId: state.bundleIds.first?.seedId)
            state.bundleIds.append(bundle)
            return bundle
        }
    }

    override func updateBundleId(id: String, name: String) async throws {
        try state.write { state in
            guard let index = state.bundleIds.firstIndex(where: { $0.id == id }) else { throw FakeCoreError.notFound("Bundle ID \(id)") }
            state.bundleIds[index].name = name
        }
    }

    override func deleteBundleId(id: String) async throws {
        state.write { state in
            state.bundleIds.removeAll { $0.id == id }
            state.bundleCapabilities[id] = nil
        }
    }

    override func fetchBundleIdCapabilities(bundleId: String) async throws -> [BundleIdCapabilityInfo] {
        state.read { $0.bundleCapabilities[bundleId] ?? [] }
    }

    override func enableCapability(bundleId: String, capabilityType: String) async throws -> BundleIdCapabilityInfo {
        let capability = BundleIdCapabilityInfo(id: "\(bundleId)_\(capabilityType)", capabilityType: capabilityType)
        state.write { state in
            var list = state.bundleCapabilities[bundleId] ?? []
            if !list.contains(where: { $0.capabilityType == capabilityType }) { list.append(capability) }
            state.bundleCapabilities[bundleId] = list
        }
        return capability
    }

    override func disableCapability(capabilityId: String) async throws {
        state.write { state in
            for key in state.bundleCapabilities.keys {
                state.bundleCapabilities[key]?.removeAll { $0.id == capabilityId }
            }
        }
    }
}

final class FakeASCCertificates: Certificates, @unchecked Sendable {

    private let team: FakeAppStoreConnectTeam
    private var state: FakeStateBox<FakeAppStoreConnectState> { team.state }

    init(team: FakeAppStoreConnectTeam) {
        self.team = team
        super.init(noHandle: .init())
    }

    required init(unsafeFromHandle handle: UInt64) {
        fatalError("Fake capabilities are never lifted from the FFI")
    }

    override func fetchCertificates() async throws -> [CertificateInfo] {
        state.read { $0.certificates }
    }

    override func fetchCertificateContent(id: String) async throws -> String? {
        state.read { $0.certificates.first { $0.id == id }?.certificateContent }
    }

    override func createCertificate(csrContent: String, certificateType: String, passTypeId: String?, merchantId: String?) async throws -> CertificateInfo {
        let serial = String(format: "%016llX", UInt64.random(in: 0...UInt64.max))
        let name = FakeAppStoreConnectCatalog.certificateDisplayName(type: certificateType, team: team.name)
        let certificate = CertificateInfo(
            id: FakeID.make("cert"), displayName: name, name: name, certificateType: certificateType,
            platform: certificateType.hasPrefix("MAC") || certificateType.hasPrefix("DEVELOPER_ID") ? "MAC_OS" : "IOS",
            serialNumber: serial, expirationDate: FakeClock.iso(Date().addingTimeInterval(365 * 86_400)),
            isActivated: true, certificateContent: FakeAppStoreConnectCatalog.fakeDERBase64(seed: serial)
        )
        state.write { $0.certificates.append(certificate) }
        return certificate
    }

    override func revokeCertificate(id: String) async throws {
        state.write { $0.certificates.removeAll { $0.id == id } }
    }
}

final class FakeASCProfiles: Profiles, @unchecked Sendable {

    private let team: FakeAppStoreConnectTeam
    private var state: FakeStateBox<FakeAppStoreConnectState> { team.state }

    init(team: FakeAppStoreConnectTeam) {
        self.team = team
        super.init(noHandle: .init())
    }

    required init(unsafeFromHandle handle: UInt64) {
        fatalError("Fake capabilities are never lifted from the FFI")
    }

    override func fetchProfiles() async throws -> [ProvisioningProfileInfo] {
        state.read { $0.profiles }
    }

    override func fetchProfileContent(id: String) async throws -> String? {
        state.read { $0.profiles.first { $0.id == id }?.profileContent }
    }

    override func createProfile(name: String, profileType: String, bundleIdId: String, certificateIds: [String], deviceIds: [String]) async throws -> ProvisioningProfileInfo {
        try state.write { state in
            guard let bundle = state.bundleIds.first(where: { $0.id == bundleIdId }) else {
                throw FakeCoreError.notFound("Bundle ID \(bundleIdId)")
            }
            let profile = ProvisioningProfileInfo(
                id: FakeID.make("profile"), name: name, profileType: profileType, profileState: "ACTIVE",
                platform: bundle.platform, uuid: UUID().uuidString.lowercased(), bundleId: bundle.identifier,
                createdDate: FakeClock.iso(Date()), expirationDate: FakeClock.iso(Date().addingTimeInterval(365 * 86_400)),
                profileContent: FakeAppStoreConnectCatalog.fakeDERBase64(seed: name)
            )
            state.profiles.append(profile)
            return profile
        }
    }

    override func deleteProfile(id: String) async throws {
        state.write { $0.profiles.removeAll { $0.id == id } }
    }
}

// MARK: - Analytics

final class FakeASCAnalytics: Analytics, @unchecked Sendable {

    private let team: FakeAppStoreConnectTeam
    private var state: FakeStateBox<FakeAppStoreConnectState> { team.state }

    init(team: FakeAppStoreConnectTeam) {
        self.team = team
        super.init(noHandle: .init())
    }

    required init(unsafeFromHandle handle: UInt64) {
        fatalError("Fake capabilities are never lifted from the FFI")
    }

    override func createAnalyticsReportRequest(appId: String, accessType: String) async throws -> AnalyticsReportRequest {
        try state.write { state in
            guard let app = state.app(appId) else { throw FakeCoreError.notFound("App \(appId)") }
            let request = FakeAppStoreConnectCatalog.addAnalytics(to: &state, app: app, accessType: accessType, clock: team.clock)
            return request
        }
    }

    override func fetchAnalyticsReportRequestsPage(appId: String, filterAccessType: String?, limit: UInt32, pageToken: String?) async throws -> AnalyticsReportRequestsPage {
        let requests = state.read { state in
            (state.analyticsRequests[appId] ?? []).filter { filterAccessType == nil || $0.accessType == filterAccessType }
        }
        return AnalyticsReportRequestsPage(requests: requests, nextToken: nil)
    }

    override func fetchAnalyticsReportsPage(requestId: String, filterCategory: String?, limit: UInt32, pageToken: String?) async throws -> AnalyticsReportsPage {
        let reports = state.read { state in
            (state.analyticsReports[requestId] ?? []).filter { filterCategory == nil || $0.category == filterCategory }
        }
        return AnalyticsReportsPage(reports: reports, nextToken: nil)
    }

    override func fetchAnalyticsReportInstancesPage(reportId: String, filterGranularity: String?, limit: UInt32, pageToken: String?) async throws -> AnalyticsReportInstancesPage {
        let instances = state.read { state in
            (state.analyticsInstances[reportId] ?? []).filter { filterGranularity == nil || $0.granularity == filterGranularity }
        }
        return AnalyticsReportInstancesPage(instances: instances, nextToken: nil)
    }

    override func fetchAnalyticsReportSegmentsPage(instanceId: String, limit: UInt32, pageToken: String?) async throws -> AnalyticsReportSegmentsPage {
        AnalyticsReportSegmentsPage(segments: state.read { $0.analyticsSegments[instanceId] ?? [] }, nextToken: nil)
    }

    override func downloadAnalyticsSegment(url: String, maxBytes: UInt64) async throws -> AnalyticsReportData {
        guard let source = state.read({ $0.segmentSources[url] }) else { throw FakeCoreError.notFound("Analytics segment") }
        return FakeAnalyticsReportGenerator.data(for: source)
    }
}
#endif
