import Foundation
import StackProtocols
import StackCoreRust

final class AppleAccountConnection: AccountConnectionProtocol, @unchecked Sendable {

    private let credentials: AppleCredentials

    /// Resolves feature flags (e.g. `useRustCoreDebugLogging`). Injected for testability.
    private let featureFlags: FeatureFlags

    /// Synchronous connectivity probe. Gates every mutating (POST/PUT/PATCH/DELETE)
    /// call via `requireOnline()` so write actions fail fast offline instead of
    /// timing out. Injected (defaults to the shared monitor) for testability.
    private let connectivity: ConnectivityProviding

    /// Lazily-built Rust core provider, reused across `validateCredentials()` and
    /// `fetchApps()` within a single connection. Only created when the flag is ON.
    private var rustProvider: StackCoreRust.Provider?

    /// Backs the Rust core's `CredentialStore` callback. Read-only bridge to
    /// `AppleCredentials`. Constructed once per connection.
    private lazy var rustCredentialStore = AppleCredentialStore(credentials: credentials)

    init(
        credentials: AppleCredentials,
        featureFlags: FeatureFlags = .shared,
        connectivity: ConnectivityProviding = ConnectivityMonitor.shared
    ) {
        self.credentials = credentials
        self.featureFlags = featureFlags
        self.connectivity = connectivity
    }

    /// Guards mutating operations: throws `OfflineError.noConnection` when the
    /// device is offline so writes fail fast (and with friendly copy) instead of
    /// hanging until a network timeout. Read/fetch methods never call this.
    private func requireOnline() throws {
        if !connectivity.isCurrentlyOnline() {
            throw OfflineError.noConnection
        }
    }

    // MARK: - AccountConnectionProtocol

    func validateCredentials() async throws {
        try requireOnline()
        let provider = try rustCoreProvider()
        try await callRustCore { try await provider.validate() }
        Log.print.info("[Apple] Credentials validated successfully (Rust core)")
    }

    func fetchApps() async throws -> [StackProtocols.AppInfo] {
        let provider = try rustCoreProvider()
        let coreApps = try await callRustCore { try await provider.fetchApps() }
        let apps = coreApps.map { app in
            StackProtocols.AppInfo(
                id: app.id,
                name: app.name,
                bundleId: app.bundleId,
                platform: app.platform
            )
        }
        Log.print.info("[Apple] Fetched \(apps.count) apps (Rust core)")
        return apps
    }

    func syncApps(accountId: String, store: BlobStore) async throws -> [StackProtocols.AppInfo] {
        let provider = try rustCoreProvider()
        let syncService = makeSyncService(provider: provider, store: store, accountId: accountId)
        let coreApps = try await callRustCore { try await syncService.syncApps() }
        let apps = coreApps.map { app in
            StackProtocols.AppInfo(
                id: app.id,
                name: app.name,
                bundleId: app.bundleId,
                platform: app.platform
            )
        }
        Log.print.info("[Apple] Synced \(apps.count) apps into store (Rust core)")
        return apps
    }

    func fetchIconUrl(appId: String) async -> String? {
        do {
            let provider = try rustCoreProvider()
            guard let meta = provider.appMetadata() else { return nil }
            return try await callRustCore { try await meta.fetchIconUrl(appId: appId) }
        } catch {
            Log.print.info("[Apple] Icon fetch failed for app \(appId) (Rust core): \(error.localizedDescription)")
            return nil
        }
    }

    func fetchAppStoreVersions(appId: String, limit: Int = 20) async throws -> [AppStoreVersionModel] {
        let provider = try rustCoreProvider()
        guard let versions = provider.appStoreVersions() else {
            throw translate(.Unsupported(message: "App Store Versions capability is not available for this provider."))
        }
        let core = try await callRustCore { try await versions.fetchVersions(appId: appId, limit: UInt32(limit)) }
        let models = core.map { Self.mapVersionInfo($0) }
        Log.print.info("[Apple] Fetched \(models.count) versions (Rust core)")
        return models
    }

    func createAppStoreVersion(request: CreateAppVersionRequest) async throws -> AppStoreVersionModel {
        try requireOnline()
        let provider = try rustCoreProvider()
        guard let versions = provider.appStoreVersions() else {
            throw translate(.Unsupported(message: "App Store Versions capability is not available for this provider."))
        }
        let core = try await callRustCore {
            try await versions.createVersion(appId: request.appId, platform: request.platform.rawValue, versionString: request.version)
        }
        Log.print.info("[Apple] Created version \(request.version) (Rust core)")
        return Self.mapVersionInfo(core)
    }

    func fetchAppStoreVersion(appId: String) async throws -> (state: String?, version: String?) {
        let provider = try rustCoreProvider()
        guard let versions = provider.appStoreVersions() else {
            throw translate(.Unsupported(message: "App Store Versions capability is not available for this provider."))
        }
        let core = try await callRustCore { try await versions.fetchVersions(appId: appId, limit: 1) }
        guard let first = core.first else { return (nil, nil) }
        return (first.appStoreState, first.versionString)
    }

    // MARK: - Delete Version

    func deleteAppStoreVersion(id: String) async throws {
        try requireOnline()
        let provider = try rustCoreProvider()
        guard let versions = provider.appStoreVersions() else {
            throw translate(.Unsupported(message: "App Store Versions capability is not available for this provider."))
        }
        try await callRustCore { try await versions.deleteVersion(id: id) }
        Log.print.info("[Apple] Deleted version \(id) (Rust core)")
        return
    }

    // MARK: - Update Version

    func updateAppStoreVersion(
        id: String,
        versionString: String? = nil,
        copyright: String? = nil,
        releaseType: String? = nil,
        earliestReleaseDate: Date? = nil
    ) async throws {
        try requireOnline()
        let provider = try rustCoreProvider()
        guard let versions = provider.appStoreVersions() else {
            throw translate(.Unsupported(message: "App Store Versions capability is not available for this provider."))
        }
        let earliestISO = earliestReleaseDate.map { ISO8601DateFormatter().string(from: $0) }
        try await callRustCore {
            try await versions.updateVersion(
                id: id,
                versionString: versionString,
                copyright: copyright,
                releaseType: releaseType,
                earliestReleaseDate: earliestISO
            )
        }
        Log.print.info("[Apple] Updated version \(id) (Rust core)")
        return
    }

    // MARK: - Localizations

    func fetchLocalizations(versionId: String) async throws -> [AppStoreLocalizationModel] {
        let provider = try rustCoreProvider()
        guard let versions = provider.appStoreVersions() else {
            throw translate(.Unsupported(message: "App Store Versions capability is not available for this provider."))
        }
        let infos = try await callRustCore { try await versions.fetchLocalizations(versionId: versionId) }
        let models = infos.map { Self.mapAppStoreLocalizationInfo($0) }
        Log.print.info("[Apple] Fetched \(models.count) localizations for version \(versionId) (Rust core)")
        return models
    }

    func updateLocalization(
        id: String,
        description: String? = nil,
        keywords: String? = nil,
        promotionalText: String? = nil,
        supportUrl: String? = nil,
        marketingUrl: String? = nil,
        whatsNew: String? = nil
    ) async throws {
        try requireOnline()
        let provider = try rustCoreProvider()
        guard let versions = provider.appStoreVersions() else {
            throw translate(.Unsupported(message: "App Store Versions capability is not available for this provider."))
        }
        try await callRustCore { try await versions.updateLocalization(id: id, description: description, keywords: keywords, promotionalText: promotionalText, supportUrl: supportUrl, marketingUrl: marketingUrl, whatsNew: whatsNew) }
        Log.print.info("[Apple] Updated localization \(id) (Rust core)")
        return
    }

    // MARK: - Builds

    func fetchBuilds(appId: String, limit: Int = 50) async throws -> [BuildModel] {
        let provider = try rustCoreProvider()
        guard let builds = provider.builds() else {
            throw translate(.Unsupported(message: "Builds capability is not available for this provider."))
        }
        let core = try await callRustCore { try await builds.fetchBuilds(appId: appId, limit: UInt32(limit)) }
        let models = core.map { Self.mapBuildInfo($0) }
        Log.print.info("[Apple] Fetched \(models.count) builds (Rust core)")
        return models
    }

    struct BuildsPage {
        let builds: [BuildModel]
        let hasNextPage: Bool
        /// Opaque token for fetching the next page. Pass as `pageAfterResponse` to the next call.
        let rawResponse: Any?
    }

    func fetchBuildsPage(
        appId: String,
        platform: String?,
        processingStates: [String]? = nil,
        limit: Int = 25,
        pageAfterResponse: Any?
    ) async throws -> BuildsPage {
        let provider = try rustCoreProvider()
        guard let builds = provider.builds() else {
            throw translate(.Unsupported(message: "Builds capability is not available for this provider."))
        }
        let token = pageAfterResponse as? String
        let page = try await callRustCore {
            try await builds.fetchBuildsPage(appId: appId, platform: platform, processingStates: processingStates ?? [], limit: UInt32(limit), pageToken: token)
        }
        let models = page.builds.map { Self.mapBuildInfo($0) }
        Log.print.info("[Apple] Fetched \(models.count) builds page (Rust core)")
        return BuildsPage(builds: models, hasNextPage: page.nextToken != nil, rawResponse: page.nextToken)
    }

    func fetchBuildDetail(buildId: String) async throws -> BuildDetailData {
        let provider = try rustCoreProvider()
        guard let builds = provider.builds() else {
            throw translate(.Unsupported(message: "Builds capability is not available for this provider."))
        }
        let detail = try await callRustCore { try await builds.fetchBuildDetail(buildId: buildId) }
        Log.print.info("[Apple] Fetched build detail \(buildId) (Rust core)")
        return BuildDetailData(
            build: Self.mapBuildInfo(detail.build),
            betaGroups: detail.betaGroups.map { Self.mapBetaGroupInfo($0) },
            localizations: detail.localizations.map { Self.mapBetaBuildLocalizationInfo($0) }
        )
    }

    func expireBuild(buildId: String) async throws {
        try requireOnline()
        let provider = try rustCoreProvider()
        guard let builds = provider.builds() else {
            throw translate(.Unsupported(message: "Builds capability is not available for this provider."))
        }
        try await callRustCore { try await builds.expireBuild(buildId: buildId) }
        Log.print.info("[Apple] Expired build \(buildId) (Rust core)")
        return
    }

    func fetchCurrentBuild(versionId: String) async throws -> BuildModel? {
        let provider = try rustCoreProvider()
        guard let builds = provider.builds() else {
            throw translate(.Unsupported(message: "Builds capability is not available for this provider."))
        }
        do {
            let info = try await callRustCore { try await builds.fetchCurrentBuild(versionId: versionId) }
            return info.map { Self.mapBuildInfo($0) }
        } catch {
            Log.print.info("[Apple] No build attached to version \(versionId) (Rust core)")
            return nil
        }
    }

    func attachBuild(versionId: String, buildId: String) async throws {
        try requireOnline()
        let provider = try rustCoreProvider()
        guard let builds = provider.builds() else {
            throw translate(.Unsupported(message: "Builds capability is not available for this provider."))
        }
        try await callRustCore { try await builds.attachBuild(versionId: versionId, buildId: buildId) }
        Log.print.info("[Apple] Attached build \(buildId) to version \(versionId) (Rust core)")
        return
    }

    // MARK: - Review Submissions

    func fetchReviewSubmissions(appId: String) async throws -> [ReviewSubmissionModel] {
        let provider = try rustCoreProvider()

        // App Store Connect always exposes the Reviews capability today, so a nil
        // here means the core genuinely cannot serve it for this provider kind.
        // We surface a clear `.Unsupported` StackError (consistent with how the
        // core signals unsupported capabilities) rather than silently falling back
        // to the Swift SDK — falling back would mask a real configuration problem
        // and defeat the purpose of the flag being ON.
        guard let reviews = provider.reviews() else {
            throw translate(.Unsupported(message: "Reviews capability is not available for this provider."))
        }

        let coreSubmissions = try await callRustCore {
            try await reviews.fetchReviewSubmissions(appId: appId)
        }

        let models = coreSubmissions.map { Self.mapReviewSubmission($0) }
        Log.print.info("[Apple] Fetched \(models.count) review submissions (Rust core)")
        return models.sorted { ($0.submittedDate ?? .distantPast) > ($1.submittedDate ?? .distantPast) }
    }

    func submitReviewSubmission(id: String) async throws {
        try requireOnline()
        let provider = try rustCoreProvider()
        guard let reviews = provider.reviews() else {
            throw translate(.Unsupported(message: "Reviews capability is not available for this provider."))
        }
        try await callRustCore { try await reviews.submitReviewSubmission(submissionId: id) }
        Log.print.info("[Apple] Resubmitted review submission \(id) (Rust core)")
        return
    }

    func discardReviewSubmission(id: String) async throws {
        try requireOnline()
        let provider = try rustCoreProvider()
        guard let reviews = provider.reviews() else {
            throw translate(.Unsupported(message: "Reviews capability is not available for this provider."))
        }
        try await callRustCore { try await reviews.discardReviewSubmission(submissionId: id) }
        Log.print.info("[Apple] Discarded review submission \(id) (Rust core)")
        return
    }

    // MARK: - TestFlight: Beta Groups

    func fetchBetaGroups(appId: String) async throws -> [BetaGroupModel] {
        let provider = try rustCoreProvider()
        guard let bg = provider.betaGroups() else {
            throw translate(.Unsupported(message: "Beta Groups capability is not available for this provider."))
        }
        let core = try await callRustCore { try await bg.fetchBetaGroups(appId: appId, limit: 50) }
        let models = core.map { Self.mapBetaGroupInfo($0) }
        Log.print.info("[Apple] Fetched \(models.count) beta groups (Rust core)")
        return models
    }

    func createBetaGroup(
        appId: String,
        name: String,
        isInternal: Bool,
        isPublicLinkEnabled: Bool = false,
        hasAccessToAllBuilds: Bool = false
    ) async throws -> BetaGroupModel {
        try requireOnline()
        let provider = try rustCoreProvider()
        guard let bg = provider.betaGroups() else {
            throw translate(.Unsupported(message: "Beta Groups capability is not available for this provider."))
        }
        let core = try await callRustCore {
            try await bg.createBetaGroup(
                appId: appId,
                name: name,
                isInternal: isInternal,
                publicLinkEnabled: isPublicLinkEnabled,
                hasAccessToAllBuilds: hasAccessToAllBuilds
            )
        }
        let model = Self.mapBetaGroupInfo(core)
        Log.print.info("[Apple] Created beta group: \(name) (Rust core)")
        return model
    }

    func updateBetaGroup(id: String, name: String?, isPublicLinkEnabled: Bool?, publicLinkLimit: Int?, isFeedbackEnabled: Bool?) async throws {
        try requireOnline()
        let provider = try rustCoreProvider()
        guard let bg = provider.betaGroups() else {
            throw translate(.Unsupported(message: "Beta Groups capability is not available for this provider."))
        }
        _ = try await callRustCore {
            try await bg.updateBetaGroup(
                groupId: id,
                name: name,
                publicLinkEnabled: isPublicLinkEnabled,
                publicLinkLimit: publicLinkLimit.map(Int32.init),
                feedbackEnabled: isFeedbackEnabled
            )
        }
        Log.print.info("[Apple] Updated beta group \(id) (Rust core)")
        return
    }

    func deleteBetaGroup(id: String) async throws {
        try requireOnline()
        let provider = try rustCoreProvider()
        guard let bg = provider.betaGroups() else {
            throw translate(.Unsupported(message: "Beta Groups capability is not available for this provider."))
        }
        try await callRustCore { try await bg.deleteBetaGroup(groupId: id) }
        Log.print.info("[Apple] Deleted beta group \(id) (Rust core)")
        return
    }

    // MARK: - TestFlight: Beta Testers

    func fetchTesterCount(groupId: String) async throws -> Int {
        let provider = try rustCoreProvider()
        guard let bg = provider.betaGroups() else {
            throw translate(.Unsupported(message: "Beta Groups capability is not available for this provider."))
        }
        let count = try await callRustCore { try await bg.fetchTesterCount(groupId: groupId) }
        Log.print.info("[Apple] Fetched tester count \(count) for group \(groupId) (Rust core)")
        return Int(count)
    }

    func fetchBetaTestersForGroup(groupId: String) async throws -> [BetaTesterModel] {
        let provider = try rustCoreProvider()
        guard let bg = provider.betaGroups() else {
            throw translate(.Unsupported(message: "Beta Groups capability is not available for this provider."))
        }
        let core = try await callRustCore { try await bg.fetchBetaTesters(groupId: groupId, limit: 200) }
        let models = core.map { Self.mapBetaTesterInfo($0) }
        Log.print.info("[Apple] Fetched \(models.count) beta testers (Rust core)")
        return models
    }

    func addTesterToGroup(email: String, firstName: String?, lastName: String?, groupId: String) async throws {
        try requireOnline()
        let provider = try rustCoreProvider()
        guard let bg = provider.betaGroups() else {
            throw translate(.Unsupported(message: "Beta Groups capability is not available for this provider."))
        }
        _ = try await callRustCore {
            try await bg.addBetaTester(
                groupId: groupId,
                email: email,
                firstName: firstName,
                lastName: lastName
            )
        }
        Log.print.info("[Apple] Added tester \(email) to group \(groupId) (Rust core)")
        return
    }

    func removeTesterFromGroup(testerId: String, groupId: String) async throws {
        try requireOnline()
        let provider = try rustCoreProvider()
        guard let bg = provider.betaGroups() else {
            throw translate(.Unsupported(message: "Beta Groups capability is not available for this provider."))
        }
        try await callRustCore { try await bg.removeBetaTester(groupId: groupId, testerId: testerId) }
        Log.print.info("[Apple] Removed tester \(testerId) from group \(groupId) (Rust core)")
        return
    }

    func resendInvite(testerId: String, appId: String) async throws {
        try requireOnline()
        let provider = try rustCoreProvider()
        guard let bg = provider.betaGroups() else {
            throw translate(.Unsupported(message: "Beta Groups capability is not available for this provider."))
        }
        try await callRustCore { try await bg.resendInvite(testerId: testerId, appId: appId) }
        Log.print.info("[Apple] Resent invite to tester \(testerId) (Rust core)")
        return
    }

    // MARK: - Team Members

    func fetchTeamMembers() async throws -> [TeamMemberModel] {
        let provider = try rustCoreProvider()
        guard let cap = provider.users() else {
            throw translate(.Unsupported(message: "Users capability is not available for this provider."))
        }
        let core = try await callRustCore { try await cap.fetchTeamMembers() }
        let models = core.map { Self.mapTeamMemberInfo($0) }
        Log.print.info("[Apple] Fetched \(models.count) team members (Rust core)")
        return models
    }

    // MARK: - User Management

    func fetchUsers() async throws -> [UserModel] {
        let provider = try rustCoreProvider()
        guard let cap = provider.users() else {
            throw translate(.Unsupported(message: "Users capability is not available for this provider."))
        }
        let core = try await callRustCore { try await cap.fetchUsers() }
        let models = core.map { Self.mapUserInfo($0) }
        Log.print.info("[Apple] Fetched \(models.count) users (Rust core)")
        return models
    }

    func inviteUser(
        email: String,
        firstName: String,
        lastName: String,
        roles: [String],
        allAppsVisible: Bool,
        provisioningAllowed: Bool
    ) async throws {
        try requireOnline()
        let provider = try rustCoreProvider()
        guard let cap = provider.users() else {
            throw translate(.Unsupported(message: "Users capability is not available for this provider."))
        }
        try await callRustCore {
            try await cap.inviteUser(
                email: email,
                firstName: firstName,
                lastName: lastName,
                roles: roles,
                allAppsVisible: allAppsVisible,
                provisioningAllowed: provisioningAllowed
            )
        }
        Log.print.info("[Apple] Invited user \(email) (Rust core)")
        return
    }

    func deleteUser(id: String, isPending: Bool) async throws {
        try requireOnline()
        let provider = try rustCoreProvider()
        guard let cap = provider.users() else {
            throw translate(.Unsupported(message: "Users capability is not available for this provider."))
        }
        try await callRustCore { try await cap.deleteUser(id: id, isPending: isPending) }
        Log.print.info("[Apple] Deleted user \(id) (isPending: \(isPending)) (Rust core)")
        return
    }

    /// Updates an **active** team member's roles and access flags. `roles` are raw
    /// ASC strings passed verbatim to the core (primary role + additional resources).
    /// Not valid for pending invitations — the ASC API cannot edit invites.
    func updateUser(
        id: String,
        roles: [String],
        allAppsVisible: Bool,
        provisioningAllowed: Bool
    ) async throws {
        try requireOnline()
        let provider = try rustCoreProvider()
        guard let cap = provider.users() else {
            throw translate(.Unsupported(message: "Users capability is not available for this provider."))
        }
        try await callRustCore {
            try await cap.updateUser(
                id: id,
                roles: roles,
                allAppsVisible: allAppsVisible,
                provisioningAllowed: provisioningAllowed
            )
        }
        Log.print.info("[Apple] Updated user \(id) (Rust core)")
        return
    }

    /// Returns the IDs of the apps a user is scoped to. Empty when the user has no
    /// visible-apps restriction configured (only meaningful when `allAppsVisible == false`).
    func fetchUserVisibleApps(id: String) async throws -> [String] {
        let provider = try rustCoreProvider()
        guard let cap = provider.users() else {
            throw translate(.Unsupported(message: "Users capability is not available for this provider."))
        }
        let appIds = try await callRustCore { try await cap.fetchUserVisibleApps(id: id) }
        Log.print.info("[Apple] Fetched \(appIds.count) visible apps for user \(id) (Rust core)")
        return appIds
    }

    /// Replaces the user's visible-apps set with `appIds` (**full replace** — an empty
    /// array clears all scoping). Only meaningful when `allAppsVisible == false`.
    func updateUserVisibleApps(id: String, appIds: [String]) async throws {
        try requireOnline()
        let provider = try rustCoreProvider()
        guard let cap = provider.users() else {
            throw translate(.Unsupported(message: "Users capability is not available for this provider."))
        }
        try await callRustCore { try await cap.updateUserVisibleApps(id: id, appIds: appIds) }
        Log.print.info("[Apple] Updated visible apps for user \(id) (\(appIds.count) apps) (Rust core)")
        return
    }

    // MARK: - TestFlight: Builds for Group

    func fetchBuildsForGroup(groupId: String) async throws -> [BuildModel] {
        let provider = try rustCoreProvider()
        guard let builds = provider.builds() else {
            throw translate(.Unsupported(message: "Builds capability is not available for this provider."))
        }
        let core = try await callRustCore { try await builds.fetchBuildsForGroup(groupId: groupId, limit: 200) }
        let models = core.map { Self.mapBuildInfo($0) }
        Log.print.info("[TestFlight] Fetched \(models.count) builds for group \(groupId) (Rust core)")
        return models
    }

    // MARK: - TestFlight: Beta Review Submission

    func submitBuildForBetaReview(buildId: String) async throws {
        try requireOnline()
        let provider = try rustCoreProvider()
        guard let builds = provider.builds() else {
            throw translate(.Unsupported(message: "Builds capability is not available for this provider."))
        }
        try await callRustCore { try await builds.submitBuildForBetaReview(buildId: buildId) }
        Log.print.info("[TestFlight] Submitted build \(buildId) for beta review (Rust core)")
        return
    }

    func fetchBetaBuildLocalizations(buildId: String) async throws -> [BetaBuildLocalizationModel] {
        let provider = try rustCoreProvider()
        guard let bbl = provider.betaBuildLocalizations() else {
            throw translate(.Unsupported(message: "Beta Build Localizations capability is not available for this provider."))
        }
        let models = try await callRustCore {
            let infos = try await bbl.fetchBetaBuildLocalizations(buildId: buildId, limit: 50)
            return infos.map { Self.mapBetaBuildLocalizationInfo($0) }
        }
        Log.print.info("[TestFlight] Fetched \(models.count) beta localizations for build \(buildId) (Rust core)")
        return models
    }

    func createBetaBuildLocalization(buildId: String, locale: String, whatsNew: String) async throws {
        try requireOnline()
        let provider = try rustCoreProvider()
        guard let bbl = provider.betaBuildLocalizations() else {
            throw translate(.Unsupported(message: "Beta Build Localizations capability is not available for this provider."))
        }
        try await callRustCore {
            _ = try await bbl.createBetaBuildLocalization(buildId: buildId, locale: locale, whatsNew: whatsNew)
        }
        Log.print.info("[TestFlight] Created beta localization (\(locale)) for build \(buildId) (Rust core)")
        return
    }

    func updateBetaBuildLocalization(id: String, whatsNew: String) async throws {
        try requireOnline()
        let provider = try rustCoreProvider()
        guard let bbl = provider.betaBuildLocalizations() else {
            throw translate(.Unsupported(message: "Beta Build Localizations capability is not available for this provider."))
        }
        try await callRustCore {
            _ = try await bbl.updateBetaBuildLocalization(id: id, whatsNew: whatsNew)
        }
        Log.print.info("[TestFlight] Updated beta localization \(id) (Rust core)")
        return
    }

    // MARK: - TestFlight: Builds for Group (continued)

    func removeBuildFromGroup(buildId: String, groupId: String) async throws {
        try requireOnline()
        let provider = try rustCoreProvider()
        guard let builds = provider.builds() else {
            throw translate(.Unsupported(message: "Builds capability is not available for this provider."))
        }
        try await callRustCore { try await builds.removeBuildFromGroup(buildId: buildId, groupId: groupId) }
        Log.print.info("[TestFlight] Removed build \(buildId) from group \(groupId) (Rust core)")
        return
    }

    func addBuildToGroups(buildId: String, groupIds: [String]) async throws {
        try requireOnline()
        let provider = try rustCoreProvider()
        guard let builds = provider.builds() else {
            throw translate(.Unsupported(message: "Builds capability is not available for this provider."))
        }
        try await callRustCore { try await builds.addBuildToGroups(buildId: buildId, groupIds: groupIds) }
        Log.print.info("[TestFlight] Added build \(buildId) to \(groupIds.count) groups (Rust core)")
        return
    }

    // MARK: - Customer Reviews

    struct CustomerReviewsPage {
        let reviews: [CustomerReviewModel]
        let hasNextPage: Bool
        /// Opaque token for fetching the next page. Pass as `pageAfterResponse` to the next call.
        let rawResponse: Any?
    }

    func fetchCustomerReviews(
        appId: String,
        sort: String = "-createdDate",
        filterRating: [String]? = nil,
        limit: Int = 50
    ) async throws -> [CustomerReviewModel] {
        let page = try await fetchCustomerReviewsPage(appId: appId, sort: sort, filterRating: filterRating, limit: limit, pageAfterResponse: nil)
        return page.reviews
    }

    func fetchCustomerReviewsPage(
        appId: String,
        sort: String = "-createdDate",
        filterRating: [String]? = nil,
        limit: Int = 50,
        pageAfterResponse: Any?
    ) async throws -> CustomerReviewsPage {
        let provider = try rustCoreProvider()
        guard let reviews = provider.reviews() else {
            throw translate(.Unsupported(message: "Reviews capability is not available for this provider."))
        }
        // Our opaque paging token IS the core's nextToken (a String). When the flag is
        // OFF the token is the SDK response; the flag state is consistent within a
        // session, so the `as? String` downcast is correct here.
        let pageToken = pageAfterResponse as? String
        let core = try await callRustCore {
            try await reviews.fetchCustomerReviewsPage(
                appId: appId,
                sort: sort,
                filterRating: filterRating ?? [],
                limit: UInt32(limit),
                pageToken: pageToken
            )
        }
        let models = core.reviews.map { Self.mapCustomerReview($0) }
        Log.print.info("[Apple] Fetched \(models.count) customer reviews (Rust core)")
        return CustomerReviewsPage(reviews: models, hasNextPage: core.nextToken != nil, rawResponse: core.nextToken)
    }

    func replyToReview(reviewId: String, responseBody: String) async throws {
        try requireOnline()
        let provider = try rustCoreProvider()
        guard let reviews = provider.reviews() else {
            throw translate(.Unsupported(message: "Reviews capability is not available for this provider."))
        }
        // Rust core returns the created/replaced ReviewResponse; this method's contract
        // is Void, so we discard it (callers re-fetch the review list to see the reply).
        _ = try await callRustCore {
            try await reviews.replyToReview(reviewId: reviewId, body: responseBody)
        }
        Log.print.info("[Apple] Replied to review \(reviewId) (Rust core)")
        return
    }

    func deleteReviewResponse(responseId: String) async throws {
        try requireOnline()
        let provider = try rustCoreProvider()
        guard let reviews = provider.reviews() else {
            throw translate(.Unsupported(message: "Reviews capability is not available for this provider."))
        }
        try await callRustCore {
            try await reviews.deleteReviewResponse(responseId: responseId)
        }
        Log.print.info("[Apple] Deleted review response \(responseId) (Rust core)")
        return
    }

    // MARK: - Accessibility Declarations

    func fetchAccessibilityDeclarations(appId: String) async throws -> [AccessibilityDeclarationModel] {
        let provider = try rustCoreProvider()
        guard let cap = provider.accessibilityDeclarations() else {
            throw translate(.Unsupported(message: "Accessibility Declarations capability is not available for this provider."))
        }
        let models = try await callRustCore {
            let infos = try await cap.fetchAccessibilityDeclarations(appId: appId, limit: 20)
            return infos.map { Self.mapAccessibilityDeclarationInfo($0) }
        }
        Log.print.info("[Apple] Fetched \(models.count) accessibility declarations for app \(appId) (Rust core)")
        return models
    }

    func updateAccessibilityDeclaration(_ model: AccessibilityDeclarationModel, publish: Bool = false) async throws {
        try requireOnline()
        let provider = try rustCoreProvider()
        guard let cap = provider.accessibilityDeclarations() else {
            throw translate(.Unsupported(message: "Accessibility Declarations capability is not available for this provider."))
        }
        _ = try await callRustCore {
            try await cap.updateAccessibilityDeclaration(
                id: model.id,
                publish: publish,
                supportsAudioDescriptions: model.supportsAudioDescriptions,
                supportsCaptions: model.supportsCaptions,
                supportsDarkInterface: model.supportsDarkInterface,
                supportsDifferentiateWithoutColor: model.supportsDifferentiateWithoutColor,
                supportsLargerText: model.supportsLargerText,
                supportsReducedMotion: model.supportsReducedMotion,
                supportsSufficientContrast: model.supportsSufficientContrast,
                supportsVoiceControl: model.supportsVoiceControl,
                supportsVoiceover: model.supportsVoiceover
            )
        }
        Log.print.info("[Apple] Updated accessibility declaration \(model.id) (Rust core)")
        return
    }

    func createAccessibilityDeclaration(appId: String, deviceFamily: String) async throws -> AccessibilityDeclarationModel {
        try requireOnline()
        // Validate the device family up front against the ASC-accepted values.
        guard Self.validDeviceFamilies.contains(deviceFamily) else {
            throw NSError(domain: "Accessibility", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid device family"])
        }

        let provider = try rustCoreProvider()
        guard let cap = provider.accessibilityDeclarations() else {
            throw translate(.Unsupported(message: "Accessibility Declarations capability is not available for this provider."))
        }
        let model = try await callRustCore {
            let info = try await cap.createAccessibilityDeclaration(appId: appId, deviceFamily: deviceFamily)
            return Self.mapAccessibilityDeclarationInfo(info)
        }
        Log.print.info("[Apple] Created accessibility declaration for \(deviceFamily) (Rust core)")
        return model
    }

    func deleteAccessibilityDeclaration(id: String) async throws {
        try requireOnline()
        let provider = try rustCoreProvider()
        guard let cap = provider.accessibilityDeclarations() else {
            throw translate(.Unsupported(message: "Accessibility Declarations capability is not available for this provider."))
        }
        try await callRustCore { try await cap.deleteAccessibilityDeclaration(id: id) }
        Log.print.info("[Apple] Deleted accessibility declaration \(id) (Rust core)")
        return
    }

    // MARK: - App Review Detail

    func fetchAppReviewDetail(versionId: String) async throws -> AppReviewDetailModel? {
        let provider = try rustCoreProvider()
        guard let versions = provider.appStoreVersions() else {
            throw translate(.Unsupported(message: "App Store Versions capability is not available for this provider."))
        }
        do {
            let info = try await callRustCore { try await versions.fetchAppReviewDetail(versionId: versionId) }
            return info.map { Self.mapAppReviewDetailInfo($0) }
        } catch {
            Log.print.info("[Apple] No review detail for version \(versionId) (Rust core)")
            return nil
        }
    }

    func updateAppReviewDetail(model: AppReviewDetailModel) async throws {
        try requireOnline()
        let provider = try rustCoreProvider()
        guard let versions = provider.appStoreVersions() else {
            throw translate(.Unsupported(message: "App Store Versions capability is not available for this provider."))
        }
        try await callRustCore {
            _ = try await versions.updateAppReviewDetail(
                detailId: model.id,
                contactFirstName: model.contactFirstName,
                contactLastName: model.contactLastName,
                contactEmail: model.contactEmail,
                contactPhone: model.contactPhone,
                notes: model.notes,
                demoAccountName: model.demoAccountName,
                demoAccountPassword: model.demoAccountPassword,
                isDemoAccountRequired: model.isDemoAccountRequired
            )
        }
        Log.print.info("[Apple] Updated review detail \(model.id) (Rust core)")
        return
    }

    // MARK: - Beta App Review Detail (TestFlight Test Information)

    func fetchBetaAppReviewDetail(appId: String) async throws -> BetaAppReviewDetailModel? {
        let provider = try rustCoreProvider()
        guard let detail = provider.betaAppReviewDetail() else {
            throw translate(.Unsupported(message: "Beta App Review Detail capability is not available for this provider."))
        }
        do {
            let info = try await callRustCore { try await detail.fetchBetaAppReviewDetail(appId: appId) }
            return Self.mapBetaAppReviewDetailInfo(info)
        } catch {
            Log.print.info("[Apple] No beta review detail for app \(appId) (Rust core)")
            return nil
        }
    }

    func updateBetaAppReviewDetail(model: BetaAppReviewDetailModel) async throws {
        try requireOnline()
        let provider = try rustCoreProvider()
        guard let detail = provider.betaAppReviewDetail() else {
            throw translate(.Unsupported(message: "Beta App Review Detail capability is not available for this provider."))
        }
        try await callRustCore {
            _ = try await detail.updateBetaAppReviewDetail(
                detailId: model.id,
                contactFirstName: model.contactFirstName,
                contactLastName: model.contactLastName,
                contactEmail: model.contactEmail,
                contactPhone: model.contactPhone,
                demoAccountName: model.demoAccountName,
                demoAccountPassword: model.demoAccountPassword,
                isDemoAccountRequired: model.isDemoAccountRequired,
                notes: model.notes
            )
        }
        Log.print.info("[Apple] Updated beta review detail \(model.id) (Rust core)")
        return
    }

    // MARK: - Beta App Localizations (TestFlight description / feedback email)

    func fetchBetaAppLocalizations(appId: String) async throws -> [BetaAppLocalizationModel] {
        let provider = try rustCoreProvider()
        guard let bal = provider.betaAppLocalizations() else {
            throw translate(.Unsupported(message: "Beta App Localizations capability is not available for this provider."))
        }
        let models = try await callRustCore {
            let infos = try await bal.fetchBetaAppLocalizations(appId: appId, limit: 50)
            return infos.map { Self.mapBetaAppLocalizationInfo($0) }
        }
        Log.print.info("[Apple] Fetched \(models.count) beta app localizations for app \(appId) (Rust core)")
        return models
    }

    func updateBetaAppLocalization(id: String, feedbackEmail: String?, description: String?) async throws {
        try requireOnline()
        let provider = try rustCoreProvider()
        guard let bal = provider.betaAppLocalizations() else {
            throw translate(.Unsupported(message: "Beta App Localizations capability is not available for this provider."))
        }
        try await callRustCore {
            _ = try await bal.updateBetaAppLocalization(id: id, feedbackEmail: feedbackEmail, description: description)
        }
        Log.print.info("[Apple] Updated beta app localization \(id) (Rust core)")
        return
    }

    func createBetaAppLocalization(
        appId: String,
        locale: String,
        feedbackEmail: String?,
        description: String?
    ) async throws -> BetaAppLocalizationModel {
        try requireOnline()
        let provider = try rustCoreProvider()
        guard let bal = provider.betaAppLocalizations() else {
            throw translate(.Unsupported(message: "Beta App Localizations capability is not available for this provider."))
        }
        let model = try await callRustCore {
            let info = try await bal.createBetaAppLocalization(appId: appId, locale: locale, feedbackEmail: feedbackEmail, description: description)
            return Self.mapBetaAppLocalizationInfo(info)
        }
        Log.print.info("[Apple] Created beta app localization \(model.id) (Rust core)")
        return model
    }

    // MARK: - Screenshot Sets

    func fetchScreenshotSets(localizationId: String) async throws -> [ScreenshotSetModel] {
        let provider = try rustCoreProvider()
        guard let versions = provider.appStoreVersions() else {
            throw translate(.Unsupported(message: "App Store Versions capability is not available for this provider."))
        }
        let sets = try await callRustCore { try await versions.fetchScreenshotSets(localizationId: localizationId) }
        let models = sets.map { Self.mapScreenshotSetInfo($0) }
        Log.print.info("[Apple] Fetched \(models.count) screenshot sets for localization \(localizationId) (Rust core)")
        return models
    }

    func deleteScreenshotSet(screenshotSetId: String) async throws {
        try requireOnline()
        let provider = try rustCoreProvider()
        guard let versions = provider.appStoreVersions() else {
            throw translate(.Unsupported(message: "App Store Versions capability is not available for this provider."))
        }
        try await callRustCore { try await versions.deleteScreenshotSet(screenshotSetId: screenshotSetId) }
        Log.print.info("[Apple] Deleted screenshot set \(screenshotSetId) (Rust core)")
    }

    func deleteScreenshot(screenshotId: String) async throws {
        try requireOnline()
        let provider = try rustCoreProvider()
        guard let versions = provider.appStoreVersions() else {
            throw translate(.Unsupported(message: "App Store Versions capability is not available for this provider."))
        }
        try await callRustCore { try await versions.deleteScreenshot(screenshotId: screenshotId) }
        Log.print.info("[Apple] Deleted screenshot \(screenshotId) (Rust core)")
    }

    // MARK: - Phased Release

    func fetchPhasedRelease(versionId: String) async throws -> PhasedReleaseModel? {
        let provider = try rustCoreProvider()
        guard let versions = provider.appStoreVersions() else {
            throw translate(.Unsupported(message: "App Store Versions capability is not available for this provider."))
        }
        do {
            let info = try await callRustCore { try await versions.fetchPhasedRelease(versionId: versionId) }
            return info.map { Self.mapPhasedReleaseInfo($0) }
        } catch {
            Log.print.info("[Apple] No phased release for version \(versionId) (Rust core)")
            return nil
        }
    }

    func createPhasedRelease(versionId: String, state: String) async throws -> PhasedReleaseModel {
        try requireOnline()
        let provider = try rustCoreProvider()
        guard let versions = provider.appStoreVersions() else {
            throw translate(.Unsupported(message: "App Store Versions capability is not available for this provider."))
        }
        let model = try await callRustCore {
            let info = try await versions.createPhasedRelease(versionId: versionId, state: state)
            return Self.mapPhasedReleaseInfo(info)
        }
        Log.print.info("[Apple] Created phased release for version \(versionId) (Rust core)")
        return model
    }

    func deletePhasedRelease(id: String) async throws {
        try requireOnline()
        let provider = try rustCoreProvider()
        guard let versions = provider.appStoreVersions() else {
            throw translate(.Unsupported(message: "App Store Versions capability is not available for this provider."))
        }
        try await callRustCore { try await versions.deletePhasedRelease(id: id) }
        Log.print.info("[Apple] Deleted phased release \(id) (Rust core)")
        return
    }

    @discardableResult
    func updatePhasedReleaseState(id: String, state: String) async throws -> PhasedReleaseModel {
        try requireOnline()
        let provider = try rustCoreProvider()
        guard let versions = provider.appStoreVersions() else {
            throw translate(.Unsupported(message: "App Store Versions capability is not available for this provider."))
        }
        let model = try await callRustCore {
            let info = try await versions.updatePhasedReleaseState(id: id, state: state)
            return Self.mapPhasedReleaseInfo(info)
        }
        Log.print.info("[Apple] Updated phased release \(id) to state \(state) (Rust core)")
        return model
    }

    // MARK: - App Info

    func fetchAppInfo(appId: String) async throws -> (AppInfoModel, AgeRatingDeclarationModel?) {
        let provider = try rustCoreProvider()
        guard let meta = provider.appMetadata() else {
            throw translate(.Unsupported(message: "App Metadata capability is not available for this provider."))
        }
        let details = try await callRustCore { try await meta.fetchAppInfo(appId: appId) }
        let ageRating = details.ageRating.map { Self.mapAgeRatingDeclarationInfo($0) }
        let appInfo = Self.mapAppInfoDetails(details)
        Log.print.info("[Apple] Fetched app info for \(appId) (Rust core)")
        return (appInfo, ageRating)
    }

    // MARK: - App Info Localizations

    func fetchAppInfoLocalizations(appInfoId: String) async throws -> [AppInfoLocalizationModel] {
        let provider = try rustCoreProvider()
        guard let meta = provider.appMetadata() else {
            throw translate(.Unsupported(message: "App Metadata capability is not available for this provider."))
        }
        let models = try await callRustCore {
            let infos = try await meta.fetchAppInfoLocalizations(appInfoId: appInfoId)
            return infos.map { Self.mapAppInfoLocalizationInfo($0) }
        }
        Log.print.info("[Apple] Fetched \(models.count) app info localizations for \(appInfoId) (Rust core)")
        return models
    }

    func updateAppInfoLocalization(id: String, name: String, subtitle: String?) async throws {
        try requireOnline()
        let provider = try rustCoreProvider()
        guard let meta = provider.appMetadata() else {
            throw translate(.Unsupported(message: "App Metadata capability is not available for this provider."))
        }
        try await callRustCore {
            _ = try await meta.updateAppInfoLocalization(id: id, name: name, subtitle: subtitle)
        }
        Log.print.info("[Apple] Updated app info localization \(id) (Rust core)")
        return
    }

    func updateAppInfoLocalizationPrivacy(
        id: String,
        privacyPolicyUrl: String?,
        privacyChoicesUrl: String?,
        privacyPolicyText: String?
    ) async throws {
        try requireOnline()
        let provider = try rustCoreProvider()
        guard let meta = provider.appMetadata() else {
            throw translate(.Unsupported(message: "App Metadata capability is not available for this provider."))
        }
        try await callRustCore {
            _ = try await meta.updateAppInfoLocalizationPrivacy(id: id, privacyPolicyUrl: privacyPolicyUrl, privacyChoicesUrl: privacyChoicesUrl, privacyPolicyText: privacyPolicyText)
        }
        Log.print.info("[Apple] Updated privacy for localization \(id) (Rust core)")
        return
    }

    func createAppInfoLocalization(
        appInfoId: String,
        locale: String,
        name: String,
        subtitle: String?
    ) async throws -> AppInfoLocalizationModel {
        try requireOnline()
        let provider = try rustCoreProvider()
        guard let meta = provider.appMetadata() else {
            throw translate(.Unsupported(message: "App Metadata capability is not available for this provider."))
        }
        let model = try await callRustCore {
            let info = try await meta.createAppInfoLocalization(appInfoId: appInfoId, locale: locale, name: name, subtitle: subtitle)
            return Self.mapAppInfoLocalizationInfo(info)
        }
        Log.print.info("[Apple] Created app info localization for \(locale) (Rust core)")
        return model
    }

    func deleteAppInfoLocalization(id: String) async throws {
        try requireOnline()
        let provider = try rustCoreProvider()
        guard let meta = provider.appMetadata() else {
            throw translate(.Unsupported(message: "App Metadata capability is not available for this provider."))
        }
        try await callRustCore {
            try await meta.deleteAppInfoLocalization(id: id)
        }
        Log.print.info("[Apple] Deleted app info localization \(id) (Rust core)")
        return
    }

    // MARK: - App Categories

    func fetchAppCategories() async throws -> [AppCategoryModel] {
        let provider = try rustCoreProvider()
        guard let meta = provider.appMetadata() else {
            throw translate(.Unsupported(message: "App Metadata capability is not available for this provider."))
        }
        let models = try await callRustCore {
            let cats = try await meta.fetchAppCategories()
            return cats.map { Self.mapAppCategoryInfo($0) }
        }
        Log.print.info("[Apple] Fetched \(models.count) app categories (Rust core)")
        return models
    }

    func updateAppInfoCategory(
        appInfoId: String,
        primaryCategoryId: String?,
        subcategoryOneId: String?,
        secondaryCategoryId: String?,
        secondarySubcategoryOneId: String?
    ) async throws {
        try requireOnline()
        let provider = try rustCoreProvider()
        guard let meta = provider.appMetadata() else {
            throw translate(.Unsupported(message: "App Metadata capability is not available for this provider."))
        }
        try await callRustCore {
            try await meta.updateAppInfoCategory(
                appInfoId: appInfoId,
                primaryCategoryId: primaryCategoryId,
                subcategoryOneId: subcategoryOneId,
                secondaryCategoryId: secondaryCategoryId,
                secondarySubcategoryOneId: secondarySubcategoryOneId
            )
        }
        Log.print.info("[Apple] Updated app info category for \(appInfoId) (Rust core)")
        return
    }

    func updateApp(id: String, contentRightsDeclaration: String? = nil, primaryLocale: String? = nil) async throws {
        try requireOnline()
        let provider = try rustCoreProvider()
        guard let meta = provider.appMetadata() else {
            throw translate(.Unsupported(message: "App Metadata capability is not available for this provider."))
        }
        try await callRustCore {
            try await meta.updateApp(id: id, contentRightsDeclaration: contentRightsDeclaration, primaryLocale: primaryLocale)
        }
        Log.print.info("[Apple] Updated app \(id) (Rust core)")
        return
    }

    func updateAgeRating(
        id: String,
        alcoholTobacco: String,
        contests: String,
        gamblingSimulated: String,
        gunsOrOtherWeapons: String,
        medicalInformation: String,
        profanity: String,
        sexualContentGraphic: String,
        sexualContentOrNudity: String,
        horrorOrFear: String,
        matureOrSuggestive: String,
        violenceCartoon: String,
        violenceRealistic: String,
        violenceGraphic: String,
        isAdvertising: Bool,
        isGambling: Bool,
        isUnrestrictedWebAccess: Bool,
        isUserGeneratedContent: Bool,
        ageRatingOverride: String
    ) async throws {
        try requireOnline()
        let provider = try rustCoreProvider()
        guard let meta = provider.appMetadata() else {
            throw translate(.Unsupported(message: "App Metadata capability is not available for this provider."))
        }
        try await callRustCore {
            try await meta.updateAgeRating(
                id: id,
                alcoholTobacco: alcoholTobacco,
                contests: contests,
                gamblingSimulated: gamblingSimulated,
                gunsOrOtherWeapons: gunsOrOtherWeapons,
                medicalInformation: medicalInformation,
                profanity: profanity,
                sexualContentGraphic: sexualContentGraphic,
                sexualContentOrNudity: sexualContentOrNudity,
                horrorOrFear: horrorOrFear,
                matureOrSuggestive: matureOrSuggestive,
                violenceCartoon: violenceCartoon,
                violenceRealistic: violenceRealistic,
                violenceGraphic: violenceGraphic,
                isAdvertising: isAdvertising,
                isGambling: isGambling,
                isUnrestrictedWebAccess: isUnrestrictedWebAccess,
                isUserGeneratedContent: isUserGeneratedContent,
                ageRatingOverride: ageRatingOverride
            )
        }
        Log.print.info("[Apple] Updated age rating \(id) (Rust core)")
        return
    }

    // MARK: - Review Submissions

    func submitForReview(appId: String, versionId: String, platform: AppPlatform?) async throws {
        try requireOnline()
        let provider = try rustCoreProvider()
        guard let versions = provider.appStoreVersions() else {
            throw translate(.Unsupported(message: "App Store Versions capability is not available for this provider."))
        }
        try await callRustCore { try await versions.submitForReview(appId: appId, versionId: versionId, platform: platform?.rawValue) }
        Log.print.info("[Apple] Submitted version \(versionId) for review (Rust core)")
        return
    }

    func cancelReview(appId: String) async throws {
        try requireOnline()
        let provider = try rustCoreProvider()
        guard let versions = provider.appStoreVersions() else {
            throw translate(.Unsupported(message: "App Store Versions capability is not available for this provider."))
        }
        try await callRustCore { try await versions.cancelReview(appId: appId) }
        Log.print.info("[Apple] Cancelled review for app \(appId) (Rust core)")
        return
    }

    func releaseVersion(versionId: String) async throws {
        try requireOnline()
        let provider = try rustCoreProvider()
        guard let versions = provider.appStoreVersions() else {
            throw translate(.Unsupported(message: "App Store Versions capability is not available for this provider."))
        }
        try await callRustCore { try await versions.releaseVersion(versionId: versionId) }
        Log.print.info("[Apple] Released version \(versionId) (Rust core)")
        return
    }

    func cancelSubmission(appId: String) async throws {
        try requireOnline()
        let provider = try rustCoreProvider()
        guard let versions = provider.appStoreVersions() else {
            throw translate(.Unsupported(message: "App Store Versions capability is not available for this provider."))
        }
        try await callRustCore { try await versions.cancelSubmission(appId: appId) }
        Log.print.info("[Apple] Cancelled submission for app \(appId) (Rust core)")
        return
    }

    func rejectVersion(versionId: String) async throws {
        try requireOnline()
        let provider = try rustCoreProvider()
        guard let versions = provider.appStoreVersions() else {
            throw translate(.Unsupported(message: "App Store Versions capability is not available for this provider."))
        }
        try await callRustCore { try await versions.rejectVersion(versionId: versionId) }
        Log.print.info("[Apple] Rejected version \(versionId) (Rust core)")
        return
    }

    func disconnect() {
        rustProvider = nil
        Log.print.info("[Apple] Disconnected")
    }

    // MARK: - Certificates

    func fetchCertificates() async throws -> [CertificateModel] {
        let provider = try rustCoreProvider()
        guard let cap = provider.certificates() else {
            throw translate(.Unsupported(message: "Certificates capability is not available for this provider."))
        }
        let models = try await callRustCore {
            let infos = try await cap.fetchCertificates()
            return infos.map { Self.mapCertificateInfo($0) }
        }
        Log.print.info("[Apple] Fetched \(models.count) certificates (Rust core)")
        return models
    }

    func fetchCertificateContent(id: String) async throws -> String? {
        let provider = try rustCoreProvider()
        guard let cap = provider.certificates() else {
            throw translate(.Unsupported(message: "Certificates capability is not available for this provider."))
        }
        let content = try await callRustCore { try await cap.fetchCertificateContent(id: id) }
        Log.print.info("[Apple] Fetched certificate content for \(id) (Rust core)")
        return content
    }

    struct CreatedCertificate {
        let certificate: CertificateModel
        let content: String?
    }

    func createCertificate(
        csrContent: String,
        certificateTypeRaw: String,
        passTypeId: String? = nil,
        merchantId: String? = nil
    ) async throws -> CreatedCertificate {
        try requireOnline()
        let provider = try rustCoreProvider()
        guard let cap = provider.certificates() else {
            throw translate(.Unsupported(message: "Certificates capability is not available for this provider."))
        }
        let created = try await callRustCore {
            let info = try await cap.createCertificate(
                csrContent: csrContent,
                certificateType: certificateTypeRaw,
                passTypeId: passTypeId,
                merchantId: merchantId
            )
            return CreatedCertificate(certificate: Self.mapCertificateInfo(info), content: info.certificateContent)
        }
        Log.print.info("[Apple] Created certificate \(created.certificate.id) (\(certificateTypeRaw)) (Rust core)")
        return created
    }

    func revokeCertificate(id: String) async throws {
        try requireOnline()
        let provider = try rustCoreProvider()
        guard let cap = provider.certificates() else {
            throw translate(.Unsupported(message: "Certificates capability is not available for this provider."))
        }
        try await callRustCore { try await cap.revokeCertificate(id: id) }
        Log.print.info("[Apple] Revoked certificate \(id) (Rust core)")
        return
    }

    // MARK: - Bundle Identifiers

    func fetchBundleIds() async throws -> [BundleIdentifierModel] {
        let provider = try rustCoreProvider()
        guard let cap = provider.bundleIds() else {
            throw translate(.Unsupported(message: "BundleIds capability is not available for this provider."))
        }
        let models = try await callRustCore {
            let infos = try await cap.fetchBundleIds()
            return infos.map { Self.mapBundleIdInfo($0) }
        }
        Log.print.info("[Apple] Fetched \(models.count) bundle identifiers (Rust core)")
        return models
    }

    func createBundleId(
        identifier: String,
        name: String,
        platformRaw: String
    ) async throws -> BundleIdentifierModel {
        try requireOnline()
        // Validate the platform up front against the ASC-accepted values.
        guard Self.validBundleIdPlatforms.contains(platformRaw) else {
            throw NSError(domain: "BundleId", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid platform: \(platformRaw)"])
        }

        let provider = try rustCoreProvider()
        guard let cap = provider.bundleIds() else {
            throw translate(.Unsupported(message: "BundleIds capability is not available for this provider."))
        }
        let model = try await callRustCore {
            let info = try await cap.createBundleId(identifier: identifier, name: name, platform: platformRaw)
            return Self.mapBundleIdInfo(info)
        }
        Log.print.info("[Apple] Created bundle identifier \(identifier) (Rust core)")
        return model
    }

    func updateBundleId(id: String, name: String) async throws {
        try requireOnline()
        let provider = try rustCoreProvider()
        guard let cap = provider.bundleIds() else {
            throw translate(.Unsupported(message: "BundleIds capability is not available for this provider."))
        }
        try await callRustCore { try await cap.updateBundleId(id: id, name: name) }
        Log.print.info("[Apple] Renamed bundle identifier \(id) (Rust core)")
        return
    }

    func deleteBundleId(id: String) async throws {
        try requireOnline()
        let provider = try rustCoreProvider()
        guard let cap = provider.bundleIds() else {
            throw translate(.Unsupported(message: "BundleIds capability is not available for this provider."))
        }
        try await callRustCore { try await cap.deleteBundleId(id: id) }
        Log.print.info("[Apple] Deleted bundle identifier \(id) (Rust core)")
        return
    }

    // Permissive response: the SDK's CapabilityType enum doesn't know newer values
    // (e.g. FONT_INSTALLATION, CARPLAY_CHARGING) so the strict decoder throws. We
    // decode the bare attributes we care about as plain strings.
    private struct CapabilitiesRawResponse: Decodable {
        let data: [Item]
        struct Item: Decodable {
            let id: String
            let attributes: Attributes?
            struct Attributes: Decodable {
                let capabilityType: String?
            }
        }
    }

    func fetchBundleIdCapabilities(bundleId: String) async throws -> [BundleIdentifierCapabilityModel] {
        let provider = try rustCoreProvider()
        guard let cap = provider.bundleIds() else {
            throw translate(.Unsupported(message: "BundleIds capability is not available for this provider."))
        }
        let models = try await callRustCore {
            let infos = try await cap.fetchBundleIdCapabilities(bundleId: bundleId)
            return infos.map { Self.mapBundleIdCapabilityInfo($0) }
        }
        Log.print.info("[Apple] Fetched \(models.count) capabilities for \(bundleId) (Rust core)")
        return models
    }

    func enableCapability(bundleId: String, capabilityTypeRaw: String) async throws -> BundleIdentifierCapabilityModel {
        try requireOnline()
        let provider = try rustCoreProvider()
        guard let cap = provider.bundleIds() else {
            throw translate(.Unsupported(message: "BundleIds capability is not available for this provider."))
        }
        let model = try await callRustCore {
            let info = try await cap.enableCapability(bundleId: bundleId, capabilityType: capabilityTypeRaw)
            return Self.mapBundleIdCapabilityInfo(info)
        }
        Log.print.info("[Apple] Enabled capability \(capabilityTypeRaw) on \(bundleId) (Rust core)")
        return model
    }

    func disableCapability(capabilityId: String) async throws {
        try requireOnline()
        let provider = try rustCoreProvider()
        guard let cap = provider.bundleIds() else {
            throw translate(.Unsupported(message: "BundleIds capability is not available for this provider."))
        }
        try await callRustCore { try await cap.disableCapability(capabilityId: capabilityId) }
        Log.print.info("[Apple] Disabled capability \(capabilityId) (Rust core)")
        return
    }

    // MARK: - Devices

    func fetchDevices() async throws -> [DeviceModel] {
        let provider = try rustCoreProvider()
        guard let cap = provider.devices() else {
            throw translate(.Unsupported(message: "Devices capability is not available for this provider."))
        }
        let models = try await callRustCore {
            let infos = try await cap.fetchDevices()
            return infos.map { Self.mapDeviceInfo($0) }
        }
        Log.print.info("[Apple] Fetched \(models.count) devices (Rust core)")
        return models
    }

    func createDevice(
        name: String,
        platformRaw: String,
        udid: String
    ) async throws -> DeviceModel {
        try requireOnline()
        // Validate the platform up front against the ASC-accepted values.
        guard Self.validBundleIdPlatforms.contains(platformRaw) else {
            throw NSError(domain: "Device", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid platform: \(platformRaw)"])
        }

        let provider = try rustCoreProvider()
        guard let cap = provider.devices() else {
            throw translate(.Unsupported(message: "Devices capability is not available for this provider."))
        }
        let model = try await callRustCore {
            let info = try await cap.createDevice(name: name, platform: platformRaw, udid: udid)
            return Self.mapDeviceInfo(info)
        }
        Log.print.info("[Apple] Registered device \(udid) (\(name)) (Rust core)")
        return model
    }

    func updateDevice(id: String, name: String?, status: String?) async throws {
        try requireOnline()
        let provider = try rustCoreProvider()
        guard let cap = provider.devices() else {
            throw translate(.Unsupported(message: "Devices capability is not available for this provider."))
        }
        try await callRustCore { try await cap.updateDevice(id: id, name: name, status: status) }
        Log.print.info("[Apple] Updated device \(id) (Rust core)")
        return
    }

    // MARK: - Provisioning Profiles

    func fetchProfiles() async throws -> [ProvisioningProfileModel] {
        let provider = try rustCoreProvider()
        guard let cap = provider.profiles() else {
            throw translate(.Unsupported(message: "Profiles capability is not available for this provider."))
        }
        let models = try await callRustCore {
            let infos = try await cap.fetchProfiles()
            return infos.map { Self.mapProvisioningProfileInfo($0) }
        }
        Log.print.info("[Apple] Fetched \(models.count) provisioning profiles (Rust core)")
        return models
    }

    struct CreatedProfile {
        let profile: ProvisioningProfileModel
        let content: String?
    }

    func createProfile(
        name: String,
        profileTypeRaw: String,
        bundleIdId: String,
        certificateIds: [String],
        deviceIds: [String]
    ) async throws -> CreatedProfile {
        try requireOnline()
        let provider = try rustCoreProvider()
        guard let cap = provider.profiles() else {
            throw translate(.Unsupported(message: "Profiles capability is not available for this provider."))
        }
        let created = try await callRustCore {
            let info = try await cap.createProfile(
                name: name,
                profileType: profileTypeRaw,
                bundleIdId: bundleIdId,
                certificateIds: certificateIds,
                deviceIds: deviceIds
            )
            return CreatedProfile(profile: Self.mapProvisioningProfileInfo(info), content: info.profileContent)
        }
        Log.print.info("[Apple] Created profile \(created.profile.id) (\(profileTypeRaw)) (Rust core)")
        return created
    }

    func deleteProfile(id: String) async throws {
        try requireOnline()
        let provider = try rustCoreProvider()
        guard let cap = provider.profiles() else {
            throw translate(.Unsupported(message: "Profiles capability is not available for this provider."))
        }
        try await callRustCore { try await cap.deleteProfile(id: id) }
        Log.print.info("[Apple] Deleted profile \(id) (Rust core)")
        return
    }

    func fetchProfileContent(id: String) async throws -> String? {
        let provider = try rustCoreProvider()
        guard let cap = provider.profiles() else {
            throw translate(.Unsupported(message: "Profiles capability is not available for this provider."))
        }
        let content = try await callRustCore { try await cap.fetchProfileContent(id: id) }
        Log.print.info("[Apple] Fetched profile content for \(id) (Rust core)")
        return content
    }

    // MARK: - Private

    /// ASC-accepted `deviceFamily` values for accessibility declarations. Mirrors the
    /// raw values of the former SDK `DeviceFamily` enum so input validation stays
    /// identical after dropping the SDK.
    static let validDeviceFamilies: Set<String> = [
        "IPHONE", "IPAD", "APPLE_TV", "APPLE_WATCH", "MAC", "VISION"
    ]

    /// ASC-accepted `BundleIdPlatform` raw values used to validate device/bundle-id
    /// platform input. Mirrors the former SDK `BundleIDPlatform` enum.
    static let validBundleIdPlatforms: Set<String> = [
        "IOS", "MAC_OS", "UNIVERSAL", "SERVICES"
    ]

    static func formatCategoryId(_ id: String) -> String {
        id.replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .map { $0.capitalized }
            .joined(separator: " ")
    }

    static func formatSubcategoryId(_ id: String, parentId: String?) -> String {
        if let parentId, id.hasPrefix(parentId + "_") {
            let suffix = String(id.dropFirst(parentId.count + 1))
            return formatCategoryId(suffix)
        }
        return formatCategoryId(id)
    }

    /// Maps a Rust-core `AppStoreVersionInfo` to the app's `AppStoreVersionModel`.
    /// The core does no date logic, so `createdDate` (raw ISO8601) is parsed here;
    /// `platform`/`appStoreState` raw strings map back to the app enums.
    static func mapVersionInfo(_ info: StackCoreRust.AppStoreVersionInfo) -> AppStoreVersionModel {
        AppStoreVersionModel(
            id: info.id,
            platform: info.platform.flatMap { AppPlatform(rawValue: $0) },
            appStoreState: info.appStoreState.flatMap { AppStoreState(rawValue: $0) },
            appVersionState: info.appVersionState,
            versionString: info.versionString,
            copyright: info.copyright,
            releaseType: info.releaseType,
            createdDate: info.createdDate.flatMap(parseISO8601Date),
            appId: info.appId
        )
    }

    /// Maps a Rust-core `ReviewSubmission` to the app's `ReviewSubmissionModel`.
    /// The core does no date logic, so the raw ISO8601 `submittedDate` string is
    /// parsed here. `appId` comes straight from the core value (it is set to the
    /// requested appId by the core).
    static func mapReviewSubmission(_ submission: StackCoreRust.ReviewSubmission) -> ReviewSubmissionModel {
        ReviewSubmissionModel(
            id: submission.id,
            appId: submission.appId,
            platform: submission.platform,
            submittedDate: submission.submittedDate.flatMap(parseISO8601Date),
            state: submission.state,
            versionString: submission.versionString,
            versionId: submission.versionId,
            submittedByName: submission.submittedByName,
            submittedByEmail: submission.submittedByEmail
        )
    }

    /// Maps a Rust-core `CustomerReview` to the app's `CustomerReviewModel`.
    /// The core does no date logic, so `createdDate`/response date (raw ISO8601)
    /// are parsed here; the developer response is flattened into the model fields.
    static func mapCustomerReview(_ review: StackCoreRust.CustomerReview) -> CustomerReviewModel {
        CustomerReviewModel(
            id: review.id,
            rating: Int(review.rating),
            title: review.title,
            body: review.body,
            reviewerNickname: review.reviewerNickname,
            createdDate: review.createdDate.flatMap(parseISO8601Date),
            territory: review.territory,
            responseId: review.response?.id,
            responseBody: review.response?.body,
            responseState: review.response?.state,
            responseDate: review.response?.lastModifiedDate.flatMap(parseISO8601Date)
        )
    }

    /// Maps a Rust-core `BuildInfo` to the app's `BuildModel`.
    ///
    /// The core does no date logic, so the raw ISO8601 `uploadedDate`/`expirationDate`/
    /// `submittedDate` strings are parsed here. Every `BuildModel` field is now fully
    /// mapped: the enrichment fields (`marketingVersion`, `platform`,
    /// `externalBuildState`, `internalBuildState`, `autoNotifyEnabled`,
    /// `betaReviewState`, `submittedDate`, the computed min-OS versions,
    /// `buildAudienceType`, `usesNonExemptEncryption`) come from the `included`
    /// relationships the core now requests (preReleaseVersion / buildBetaDetail /
    /// betaAppReviewSubmission), and `iconUrl` is passed through unchanged because the
    /// core already computed it from the build's `iconAssetToken` template.
    static func mapBuildInfo(_ info: StackCoreRust.BuildInfo) -> BuildModel {
        BuildModel(
            id: info.id,
            version: info.version,
            marketingVersion: info.marketingVersion,
            processingState: info.processingState,
            uploadedDate: info.uploadedDate.flatMap(parseISO8601Date),
            iconUrl: info.iconUrl,
            platform: info.platform,
            externalBuildState: info.externalBuildState,
            betaReviewState: info.betaReviewState,
            submittedDate: info.submittedDate.flatMap(parseISO8601Date),
            expirationDate: info.expirationDate.flatMap(parseISO8601Date),
            isExpired: info.expired ?? false,
            minOsVersion: info.minOsVersion,
            computedMinMacOsVersion: info.computedMinMacOsVersion,
            computedMinVisionOsVersion: info.computedMinVisionOsVersion,
            buildAudienceType: info.buildAudienceType,
            usesNonExemptEncryption: info.usesNonExemptEncryption,
            internalBuildState: info.internalBuildState,
            autoNotifyEnabled: info.autoNotifyEnabled
        )
    }

    /// Maps a Rust-core `BetaGroupInfo` to the app's `BetaGroupModel`.
    ///
    /// The core does no date logic, so the raw ISO8601 `createdDate` string is parsed
    /// here, and the optional core flags are defaulted to match the Swift-SDK path
    /// (`?? false` / `?? ""`).
    ///
    /// Known Rust-path degradation: the core does not expose `publicLinkId`,
    /// `publicLinkLimit`, `isPublicLinkLimitEnabled`, `testerCount` or `buildCount`
    /// (the last two come from ASC relationship paging meta the core does not request),
    /// so those are left at sensible defaults (`nil`/`false`) on the Rust path.
    static func mapBetaGroupInfo(_ info: StackCoreRust.BetaGroupInfo) -> BetaGroupModel {
        BetaGroupModel(
            id: info.id,
            name: info.name ?? "",
            isInternalGroup: info.isInternalGroup ?? false,
            createdDate: info.createdDate.flatMap(parseISO8601Date),
            hasAccessToAllBuilds: info.hasAccessToAllBuilds ?? false,
            isPublicLinkEnabled: info.publicLinkEnabled ?? false,
            publicLink: info.publicLink,
            publicLinkId: nil,                  // degraded: core does not provide
            publicLinkLimit: nil,               // degraded: core does not provide
            isPublicLinkLimitEnabled: false,    // degraded: core does not provide
            isFeedbackEnabled: info.feedbackEnabled ?? false,
            testerCount: nil,                   // degraded: core does not provide
            buildCount: nil                     // degraded: core does not provide
        )
    }

    /// Maps a Rust-core `TeamMemberInfo` to the app's `TeamMemberModel`.
    /// Full fidelity: every field maps 1:1 (no date logic needed).
    static func mapTeamMemberInfo(_ info: StackCoreRust.TeamMemberInfo) -> TeamMemberModel {
        TeamMemberModel(
            id: info.id,
            firstName: info.firstName,
            lastName: info.lastName,
            username: info.username,
            roles: info.roles
        )
    }

    /// Maps a Rust-core `UserInfo` to the app's `UserModel`.
    /// The core does no date logic, so the raw ISO8601 `expirationDate` string is
    /// parsed here via `parseISO8601Date`; every other field maps 1:1.
    static func mapUserInfo(_ info: StackCoreRust.UserInfo) -> UserModel {
        UserModel(
            id: info.id,
            firstName: info.firstName,
            lastName: info.lastName,
            email: info.email,
            roles: info.roles,
            allAppsVisible: info.allAppsVisible,
            provisioningAllowed: info.provisioningAllowed,
            isPending: info.isPending,
            expirationDate: info.expirationDate.flatMap(parseISO8601Date)
        )
    }

    /// Maps a Rust-core `DeviceInfo` to the app's `DeviceModel`. Every field maps
    /// 1:1 except `addedDate`, which arrives as a raw ISO8601 string and is parsed
    /// here via `parseISO8601Date` (the core does no date logic). `status` already
    /// carries the core's default, so no fallback is needed here.
    static func mapDeviceInfo(_ info: StackCoreRust.DeviceInfo) -> DeviceModel {
        DeviceModel(
            id: info.id,
            name: info.name,
            udid: info.udid,
            platform: info.platform,
            deviceClass: info.deviceClass,
            model: info.model,
            status: info.status,
            addedDate: info.addedDate.flatMap(parseISO8601Date)
        )
    }

    /// Maps a Rust-core `BundleIdInfo` to the app's `BundleIdentifierModel`. Every
    /// field maps 1:1 and mirrors the inline SDK mapping in `fetchBundleIds`/
    /// `createBundleId` (`identifier`, `name`, `platform` are non-optional on the
    /// core side with an empty-string fallback already applied at the wire boundary;
    /// `seedId` is optional and passes straight through).
    static func mapBundleIdInfo(_ info: StackCoreRust.BundleIdInfo) -> BundleIdentifierModel {
        BundleIdentifierModel(
            id: info.id,
            identifier: info.identifier,
            name: info.name,
            platform: info.platform,
            seedId: info.seedId
        )
    }

    /// Maps a Rust-core `CertificateInfo` to the app's `CertificateModel`. Mirrors the
    /// inline SDK mapping in `fetchCertificates`/`createCertificate`. The core already
    /// applies the `displayName` fallback to `name`, so it passes straight through. The
    /// raw ISO8601 `expirationDate` string is parsed via `parseISO8601Date` (the model's
    /// `expirationDate` is `Date?`).
    static func mapCertificateInfo(_ info: StackCoreRust.CertificateInfo) -> CertificateModel {
        CertificateModel(
            id: info.id,
            displayName: info.displayName,
            name: info.name,
            certificateType: info.certificateType,
            platform: info.platform,
            serialNumber: info.serialNumber,
            expirationDate: info.expirationDate.flatMap { Self.parseISO8601Date($0) },
            isActivated: info.isActivated
        )
    }

    /// Maps a Rust-core `ProvisioningProfileInfo` to the app's `ProvisioningProfileModel`.
    /// Mirrors the inline SDK mapping in `fetchProfiles`/`createProfile`. The raw ISO8601
    /// `createdDate`/`expirationDate` strings are parsed via `parseISO8601Date` (both model
    /// fields are `Date?`); `profileContent` is not a field on the model so it is omitted here.
    static func mapProvisioningProfileInfo(_ info: StackCoreRust.ProvisioningProfileInfo) -> ProvisioningProfileModel {
        ProvisioningProfileModel(
            id: info.id,
            name: info.name,
            profileType: info.profileType,
            profileState: info.profileState,
            platform: info.platform,
            uuid: info.uuid,
            bundleId: info.bundleId,
            createdDate: info.createdDate.flatMap { Self.parseISO8601Date($0) },
            expirationDate: info.expirationDate.flatMap { Self.parseISO8601Date($0) }
        )
    }

    /// Maps a Rust-core `BundleIdCapabilityInfo` to the app's
    /// `BundleIdentifierCapabilityModel`. Both fields map 1:1.
    static func mapBundleIdCapabilityInfo(_ info: StackCoreRust.BundleIdCapabilityInfo) -> BundleIdentifierCapabilityModel {
        BundleIdentifierCapabilityModel(
            id: info.id,
            capabilityType: info.capabilityType
        )
    }

    /// Maps a Rust-core `BetaBuildLocalizationInfo` to the app's `BetaBuildLocalizationModel`.
    /// Full fidelity: the core provides every field this model needs, so they map 1:1.
    static func mapBetaBuildLocalizationInfo(_ info: StackCoreRust.BetaBuildLocalizationInfo) -> BetaBuildLocalizationModel {
        BetaBuildLocalizationModel(
            id: info.id,
            locale: info.locale,
            whatsNew: info.whatsNew
        )
    }

    /// Maps a Rust-core `BetaAppLocalizationInfo` to the app's `BetaAppLocalizationModel`.
    /// Full fidelity: the core provides every field this model needs, so they map 1:1.
    static func mapBetaAppLocalizationInfo(_ info: StackCoreRust.BetaAppLocalizationInfo) -> BetaAppLocalizationModel {
        BetaAppLocalizationModel(
            id: info.id,
            locale: info.locale,
            feedbackEmail: info.feedbackEmail,
            description: info.description
        )
    }

    /// Maps a Rust-core `AccessibilityDeclarationInfo` to the app's
    /// `AccessibilityDeclarationModel`. Full fidelity: every field (id +
    /// deviceFamily + optional state + the 9 support booleans) maps 1:1.
    static func mapAccessibilityDeclarationInfo(_ info: StackCoreRust.AccessibilityDeclarationInfo) -> AccessibilityDeclarationModel {
        AccessibilityDeclarationModel(
            id: info.id,
            deviceFamily: info.deviceFamily,
            state: info.state,
            supportsAudioDescriptions: info.supportsAudioDescriptions,
            supportsCaptions: info.supportsCaptions,
            supportsDarkInterface: info.supportsDarkInterface,
            supportsDifferentiateWithoutColor: info.supportsDifferentiateWithoutColor,
            supportsLargerText: info.supportsLargerText,
            supportsReducedMotion: info.supportsReducedMotion,
            supportsSufficientContrast: info.supportsSufficientContrast,
            supportsVoiceControl: info.supportsVoiceControl,
            supportsVoiceover: info.supportsVoiceover
        )
    }

    /// Maps a Rust-core `AppStoreLocalizationInfo` to the app's `AppStoreLocalizationModel`.
    /// Full fidelity: every field (id + 7 optional strings) maps 1:1.
    static func mapAppStoreLocalizationInfo(_ info: StackCoreRust.AppStoreLocalizationInfo) -> AppStoreLocalizationModel {
        AppStoreLocalizationModel(
            id: info.id,
            locale: info.locale,
            description: info.description,
            keywords: info.keywords,
            promotionalText: info.promotionalText,
            supportUrl: info.supportUrl,
            marketingUrl: info.marketingUrl,
            whatsNew: info.whatsNew
        )
    }

    /// Maps a Rust-core `ScreenshotInfo` to the app's `ScreenshotModel`.
    /// The numeric dimensions arrive as `Int32?` over FFI and are widened to `Int?`.
    static func mapScreenshotInfo(_ s: StackCoreRust.ScreenshotInfo) -> ScreenshotModel {
        ScreenshotModel(
            id: s.id,
            imageUrl: s.imageUrl,
            fileName: s.fileName,
            fileSize: s.fileSize.map(Int.init),
            width: s.width.map(Int.init),
            height: s.height.map(Int.init)
        )
    }

    /// Maps a Rust-core `ScreenshotSetInfo` to the app's `ScreenshotSetModel`,
    /// recursively mapping each nested screenshot.
    static func mapScreenshotSetInfo(_ info: StackCoreRust.ScreenshotSetInfo) -> ScreenshotSetModel {
        ScreenshotSetModel(
            id: info.id,
            displayType: info.displayType,
            screenshots: info.screenshots.map { Self.mapScreenshotInfo($0) }
        )
    }

    /// Maps a Rust-core `AppInfoLocalizationInfo` to the app's `AppInfoLocalizationModel`.
    /// Full fidelity: the core provides every field this model needs, so they map 1:1.
    static func mapAppInfoLocalizationInfo(_ info: StackCoreRust.AppInfoLocalizationInfo) -> AppInfoLocalizationModel {
        AppInfoLocalizationModel(
            id: info.id,
            locale: info.locale,
            name: info.name,
            subtitle: info.subtitle,
            privacyPolicyUrl: info.privacyPolicyUrl,
            privacyChoicesUrl: info.privacyChoicesUrl,
            privacyPolicyText: info.privacyPolicyText
        )
    }

    /// Maps a Rust-core `AgeRatingDeclarationInfo` to the app's `AgeRatingDeclarationModel`.
    /// Full fidelity: every field (id + 13 string ratings + 4 bool flags + override)
    /// maps 1:1 — the Rust field names match the model's exactly.
    static func mapAgeRatingDeclarationInfo(_ info: StackCoreRust.AgeRatingDeclarationInfo) -> AgeRatingDeclarationModel {
        AgeRatingDeclarationModel(
            id: info.id,
            alcoholTobaccoOrDrugUseOrReferences: info.alcoholTobaccoOrDrugUseOrReferences,
            contests: info.contests,
            gamblingSimulated: info.gamblingSimulated,
            gunsOrOtherWeapons: info.gunsOrOtherWeapons,
            medicalOrTreatmentInformation: info.medicalOrTreatmentInformation,
            profanityOrCrudeHumor: info.profanityOrCrudeHumor,
            sexualContentGraphicAndNudity: info.sexualContentGraphicAndNudity,
            sexualContentOrNudity: info.sexualContentOrNudity,
            horrorOrFearThemes: info.horrorOrFearThemes,
            matureOrSuggestiveThemes: info.matureOrSuggestiveThemes,
            violenceCartoonOrFantasy: info.violenceCartoonOrFantasy,
            violenceRealistic: info.violenceRealistic,
            violenceRealisticProlongedGraphicOrSadistic: info.violenceRealisticProlongedGraphicOrSadistic,
            isAdvertising: info.isAdvertising,
            isGambling: info.isGambling,
            isUnrestrictedWebAccess: info.isUnrestrictedWebAccess,
            isUserGeneratedContent: info.isUserGeneratedContent,
            ageRatingOverrideV2: info.ageRatingOverrideV2
        )
    }

    /// Maps a Rust-core `AppInfoDetails` to the app's `AppInfoModel`. The core does no
    /// display formatting, so category/subcategory *names* are computed here from their
    /// IDs via the existing `formatCategoryId`/`formatSubcategoryId` helpers — mirroring
    /// exactly what the Swift-SDK body builds. Localizations are mapped via the shared
    /// `mapAppInfoLocalizationInfo`. (`AppInfoModel` has no `secondarySubcategoryOneName`.)
    static func mapAppInfoDetails(_ d: StackCoreRust.AppInfoDetails) -> AppInfoModel {
        AppInfoModel(
            id: d.appInfoId,
            appId: d.appId,
            sku: d.sku,
            primaryLocale: d.primaryLocale,
            contentRightsDeclaration: d.contentRightsDeclaration,
            primaryCategoryId: d.primaryCategoryId,
            primaryCategoryName: d.primaryCategoryId.map { Self.formatCategoryId($0) },
            primarySubcategoryOneId: d.primarySubcategoryOneId,
            primarySubcategoryOneName: d.primarySubcategoryOneId.map { Self.formatSubcategoryId($0, parentId: d.primaryCategoryId) },
            secondaryCategoryId: d.secondaryCategoryId,
            secondaryCategoryName: d.secondaryCategoryId.map { Self.formatCategoryId($0) },
            secondarySubcategoryOneId: d.secondarySubcategoryOneId,
            ageRatingDeclarationId: d.ageRatingDeclarationId,
            appStoreAgeRating: d.appStoreAgeRating,
            localizations: d.localizations.map { Self.mapAppInfoLocalizationInfo($0) }
        )
    }

    /// Maps a Rust-core `AppCategoryInfo` to the app's `AppCategoryModel`, nesting each
    /// subcategory id as a leaf `AppCategoryModel`. Mirrors the Swift-SDK body.
    static func mapAppCategoryInfo(_ info: StackCoreRust.AppCategoryInfo) -> AppCategoryModel {
        AppCategoryModel(
            id: info.id,
            subcategories: info.subcategoryIds.map { AppCategoryModel(id: $0) }
        )
    }

    /// Maps a Rust-core `BetaAppReviewDetailInfo` to the app's `BetaAppReviewDetailModel`.
    /// Full fidelity: the core provides every field this model needs, so they map 1:1,
    /// passing all eight optional fields straight through.
    static func mapBetaAppReviewDetailInfo(_ info: StackCoreRust.BetaAppReviewDetailInfo) -> BetaAppReviewDetailModel {
        BetaAppReviewDetailModel(
            id: info.id,
            contactFirstName: info.contactFirstName,
            contactLastName: info.contactLastName,
            contactEmail: info.contactEmail,
            contactPhone: info.contactPhone,
            demoAccountName: info.demoAccountName,
            demoAccountPassword: info.demoAccountPassword,
            isDemoAccountRequired: info.isDemoAccountRequired,
            notes: info.notes
        )
    }

    /// Maps a Rust-core `AppReviewDetailInfo` to the app's `AppReviewDetailModel`.
    /// Full fidelity: the core provides every field this model needs, so they map 1:1,
    /// passing all eight optional fields straight through.
    static func mapAppReviewDetailInfo(_ info: StackCoreRust.AppReviewDetailInfo) -> AppReviewDetailModel {
        AppReviewDetailModel(
            id: info.id,
            contactFirstName: info.contactFirstName,
            contactLastName: info.contactLastName,
            contactEmail: info.contactEmail,
            contactPhone: info.contactPhone,
            notes: info.notes,
            demoAccountName: info.demoAccountName,
            demoAccountPassword: info.demoAccountPassword,
            isDemoAccountRequired: info.isDemoAccountRequired
        )
    }

    /// Maps a Rust-core `BetaTesterInfo` to the app's `BetaTesterModel`. Full fidelity:
    /// the core provides every field this model needs, so they map 1:1.
    static func mapBetaTesterInfo(_ info: StackCoreRust.BetaTesterInfo) -> BetaTesterModel {
        BetaTesterModel(
            id: info.id,
            firstName: info.firstName,
            lastName: info.lastName,
            email: info.email,
            inviteType: info.inviteType,
            state: info.state
        )
    }

    /// Maps a Rust-core `PhasedReleaseInfo` to the app's `PhasedReleaseModel`.
    /// The core hands back the phased-release state and start date as raw strings,
    /// so we parse the state into `PhasedReleaseStatus` and the ISO8601 start date
    /// into `Date`, and widen the `Int32` counters to `Int`. Any unparseable /
    /// absent optional collapses to `nil`.
    static func mapPhasedReleaseInfo(_ info: StackCoreRust.PhasedReleaseInfo) -> PhasedReleaseModel {
        PhasedReleaseModel(
            id: info.id,
            state: info.state.flatMap { PhasedReleaseStatus(rawValue: $0) },
            startDate: info.startDate.flatMap(parseISO8601Date),
            totalPauseDuration: info.totalPauseDuration.map(Int.init),
            currentDayNumber: info.currentDayNumber.map(Int.init)
        )
    }

    /// App Store Connect timestamps may or may not include fractional seconds
    /// (e.g. `2024-01-15T10:30:00Z` vs `2024-01-15T10:30:00.123Z`). A single
    /// `ISO8601DateFormatter` cannot tolerate both, so we try with fractional
    /// seconds first, then fall back to the plain internet date-time format.
    static func parseISO8601Date(_ string: String) -> Date? {
        let withFractional = ISO8601DateFormatter()
        withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFractional.date(from: string) {
            return date
        }

        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: string)
    }

    // MARK: - Analytics

    /// A single page of analytics report requests plus the opaque forward
    /// pagination token. `hasNextPage` mirrors `BuildsPage` so callers can drive
    /// infinite scroll with the same idiom.
    struct AnalyticsReportRequestsPageResult {
        let requests: [AnalyticsReportRequestModel]
        let hasNextPage: Bool
        let nextToken: String?
    }

    struct AnalyticsReportsPageResult {
        let reports: [AnalyticsReportModel]
        let hasNextPage: Bool
        let nextToken: String?
    }

    struct AnalyticsReportInstancesPageResult {
        let instances: [AnalyticsReportInstanceModel]
        let hasNextPage: Bool
        let nextToken: String?
    }

    struct AnalyticsReportSegmentsPageResult {
        let segments: [AnalyticsReportSegmentModel]
        let hasNextPage: Bool
        let nextToken: String?
    }

    /// Requests Apple to start generating analytics reports for `appId`.
    /// `accessType` is the raw wire value: `ONGOING` or `ONE_TIME_SNAPSHOT`.
    /// Apple generates *all* report categories for the app; category/granularity
    /// are browsing filters applied later, not parameters of this request.
    func createAnalyticsReportRequest(appId: String, accessType: String) async throws -> AnalyticsReportRequestModel {
        try requireOnline()
        let provider = try rustCoreProvider()
        guard let analytics = provider.analytics() else {
            throw translate(.Unsupported(message: "Analytics capability is not available for this provider."))
        }
        let core = try await callRustCore { try await analytics.createAnalyticsReportRequest(appId: appId, accessType: accessType) }
        Log.print.info("[Apple] Created analytics report request \(core.id) (Rust core)")
        return Self.mapAnalyticsReportRequest(core)
    }

    func fetchAnalyticsReportRequestsPage(
        appId: String,
        filterAccessType: String? = nil,
        limit: Int = 50,
        pageToken: String? = nil
    ) async throws -> AnalyticsReportRequestsPageResult {
        let provider = try rustCoreProvider()
        guard let analytics = provider.analytics() else {
            throw translate(.Unsupported(message: "Analytics capability is not available for this provider."))
        }
        let page = try await callRustCore {
            try await analytics.fetchAnalyticsReportRequestsPage(appId: appId, filterAccessType: filterAccessType, limit: UInt32(limit), pageToken: pageToken)
        }
        let models = page.requests.map { Self.mapAnalyticsReportRequest($0) }
        Log.print.info("[Apple] Fetched \(models.count) analytics report requests page (Rust core)")
        return AnalyticsReportRequestsPageResult(requests: models, hasNextPage: page.nextToken != nil, nextToken: page.nextToken)
    }

    func fetchAnalyticsReportsPage(
        requestId: String,
        filterCategory: String? = nil,
        limit: Int = 50,
        pageToken: String? = nil
    ) async throws -> AnalyticsReportsPageResult {
        let provider = try rustCoreProvider()
        guard let analytics = provider.analytics() else {
            throw translate(.Unsupported(message: "Analytics capability is not available for this provider."))
        }
        let page = try await callRustCore {
            try await analytics.fetchAnalyticsReportsPage(requestId: requestId, filterCategory: filterCategory, limit: UInt32(limit), pageToken: pageToken)
        }
        let models = page.reports.map { Self.mapAnalyticsReport($0) }
        Log.print.info("[Apple] Fetched \(models.count) analytics reports page (Rust core)")
        return AnalyticsReportsPageResult(reports: models, hasNextPage: page.nextToken != nil, nextToken: page.nextToken)
    }

    func fetchAnalyticsReportInstancesPage(
        reportId: String,
        filterGranularity: String? = nil,
        limit: Int = 50,
        pageToken: String? = nil
    ) async throws -> AnalyticsReportInstancesPageResult {
        let provider = try rustCoreProvider()
        guard let analytics = provider.analytics() else {
            throw translate(.Unsupported(message: "Analytics capability is not available for this provider."))
        }
        let page = try await callRustCore {
            try await analytics.fetchAnalyticsReportInstancesPage(reportId: reportId, filterGranularity: filterGranularity, limit: UInt32(limit), pageToken: pageToken)
        }
        let models = page.instances.map { Self.mapAnalyticsReportInstance($0) }
        Log.print.info("[Apple] Fetched \(models.count) analytics report instances page (Rust core)")
        return AnalyticsReportInstancesPageResult(instances: models, hasNextPage: page.nextToken != nil, nextToken: page.nextToken)
    }

    func fetchAnalyticsReportSegmentsPage(
        instanceId: String,
        limit: Int = 50,
        pageToken: String? = nil
    ) async throws -> AnalyticsReportSegmentsPageResult {
        let provider = try rustCoreProvider()
        guard let analytics = provider.analytics() else {
            throw translate(.Unsupported(message: "Analytics capability is not available for this provider."))
        }
        let page = try await callRustCore {
            try await analytics.fetchAnalyticsReportSegmentsPage(instanceId: instanceId, limit: UInt32(limit), pageToken: pageToken)
        }
        let models = page.segments.map { Self.mapAnalyticsReportSegment($0) }
        Log.print.info("[Apple] Fetched \(models.count) analytics report segments page (Rust core)")
        return AnalyticsReportSegmentsPageResult(segments: models, hasNextPage: page.nextToken != nil, nextToken: page.nextToken)
    }

    /// Downloads and parses a segment's pre-signed S3 URL. The core performs the
    /// no-auth GET + gunzip and returns the parsed TSV as `headers` + `rows`;
    /// there is no raw file to persist, so callers reconstruct one (e.g. CSV).
    func downloadAnalyticsSegment(url: String, maxBytes: UInt64) async throws -> AnalyticsReportContent {
        let provider = try rustCoreProvider()
        guard let analytics = provider.analytics() else {
            throw translate(.Unsupported(message: "Analytics capability is not available for this provider."))
        }
        let data = try await callRustCore { try await analytics.downloadAnalyticsSegment(url: url, maxBytes: maxBytes) }
        Log.print.info("[Apple] Downloaded analytics segment: \(data.rowCount) rows (Rust core)")
        return AnalyticsReportContent(headers: data.headers, rows: data.rows, rowCount: Int(data.rowCount))
    }

    // MARK: - Analytics mapping

    static func mapAnalyticsReportRequest(_ core: StackCoreRust.AnalyticsReportRequest) -> AnalyticsReportRequestModel {
        AnalyticsReportRequestModel(id: core.id, accessType: core.accessType, stoppedDueToInactivity: core.stoppedDueToInactivity)
    }

    static func mapAnalyticsReport(_ core: StackCoreRust.AnalyticsReport) -> AnalyticsReportModel {
        AnalyticsReportModel(id: core.id, name: core.name, category: core.category)
    }

    static func mapAnalyticsReportInstance(_ core: StackCoreRust.AnalyticsReportInstance) -> AnalyticsReportInstanceModel {
        AnalyticsReportInstanceModel(id: core.id, granularity: core.granularity, processingDate: core.processingDate)
    }

    static func mapAnalyticsReportSegment(_ core: StackCoreRust.AnalyticsReportSegment) -> AnalyticsReportSegmentModel {
        AnalyticsReportSegmentModel(id: core.id, url: core.url, checksum: core.checksum, sizeInBytes: core.sizeInBytes.map(Int.init))
    }

    // MARK: - Rust core

    /// Lazily builds and caches the Rust core `Provider` for App Store Connect,
    /// reusing it across `validateCredentials()` and `fetchApps()` within this
    /// connection. `connect(...)` reads credentials synchronously via the
    /// `AppleCredentialStore` callback. The `accountId` is the issuer ID — a stable
    /// per-connection identifier (the store is built per connection).
    private func rustCoreProvider() throws -> StackCoreRust.Provider {
        if let rustProvider {
            return rustProvider
        }
        do {
            let provider = try connect(
                kind: .appStoreConnect,
                accountId: credentials.issuerID,
                store: rustCredentialStore,
                debugLogger: featureFlags.isEnabled(.useRustCoreDebugLogging) ? RustCoreDebugLogger() : nil
            )
            rustProvider = provider
            return provider
        } catch let error as StackError {
            throw translate(error)
        }
    }

    /// Runs a Rust core async call, translating `StackError` into the app's error
    /// handling so callers behave the same as with the Swift SDK path.
    private func callRustCore<T>(
        _ operation: () async throws -> T
    ) async throws -> T {
        do {
            return try await operation()
        } catch let error as StackError {
            throw translate(error)
        }
    }

    /// Translates a Rust-core `StackError` for the app.
    ///
    /// `StackError` already conforms to `LocalizedError`, and every existing Apple
    /// call site surfaces failures via `error.localizedDescription` / generic
    /// `catch`. We therefore preserve the typed error (so `errorDescription` flows
    /// through unchanged) while logging it at the boundary. This keeps caller
    /// behaviour identical to the Swift SDK path and gives us a single place to add
    /// richer mapping (e.g. pending-agreement handling) if the migration expands.
    private func translate(_ error: StackError) -> Error {
        Log.print.error("[Apple] Rust core error: \(error.localizedDescription)")
        return error
    }
}

// MARK: - Analytics Models

/// A report request the developer has asked Apple to generate for an app.
/// `accessType` is the raw wire value (`ONGOING` / `ONE_TIME_SNAPSHOT`).
struct AnalyticsReportRequestModel: Identifiable, Equatable, Hashable {
    let id: String
    let accessType: String
    let stoppedDueToInactivity: Bool
}

/// A single report available under a request. `category` is the raw ASC value
/// (e.g. `APP_USAGE`); `name` is the report's display name.
struct AnalyticsReportModel: Identifiable, Equatable, Hashable {
    let id: String
    let name: String
    let category: String
}

/// A dated instance of a report at a given granularity (`DAILY`/`WEEKLY`/`MONTHLY`).
struct AnalyticsReportInstanceModel: Identifiable, Equatable, Hashable {
    let id: String
    let granularity: String
    let processingDate: String?
}

/// A downloadable segment of an instance. `url` is a pre-signed S3 URL; the core
/// handles the no-auth GET + gunzip when downloading.
struct AnalyticsReportSegmentModel: Identifiable, Equatable, Hashable {
    let id: String
    let url: String
    let checksum: String?
    let sizeInBytes: Int?
}

/// The parsed contents of a downloaded segment (generic tab-delimited data
/// reconstructed as headers + rows). There is no raw file — callers materialize
/// one (e.g. CSV) from this.
struct AnalyticsReportContent: Equatable, Hashable {
    let headers: [String]
    let rows: [[String]]
    let rowCount: Int
}
