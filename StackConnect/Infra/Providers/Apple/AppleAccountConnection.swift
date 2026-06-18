import Foundation
import AppStoreConnect_Swift_SDK
import StackProtocols
import StackCoreRust

final class AppleAccountConnection: AccountConnectionProtocol, @unchecked Sendable {

    private let credentials: AppleCredentials
    private var provider: APIProvider?

    /// Test-only window onto whether the Swift SDK provider has been established.
    /// Used by `RustCoreStranglerTests` to assert the Rust-core validate path seeds
    /// `self.provider` (issue #84) without exposing the provider itself.
    var hasSwiftProviderForTesting: Bool { provider != nil }

    /// Resolves the `useRustCoreForAppleApps` flag. Injected for testability so the
    /// strangler path can be exercised in BOTH states.
    private let featureFlags: FeatureFlags

    /// Lazily-built Rust core provider, reused across `validateCredentials()` and
    /// `fetchApps()` within a single connection. Only created when the flag is ON.
    private var rustProvider: StackCoreRust.Provider?

    /// Backs the Rust core's `CredentialStore` callback. Read-only bridge to
    /// `AppleCredentials`. Constructed once per connection.
    private lazy var rustCredentialStore = AppleCredentialStore(credentials: credentials)

    init(
        credentials: AppleCredentials,
        featureFlags: FeatureFlags = .shared
    ) {
        self.credentials = credentials
        self.featureFlags = featureFlags
    }

    // MARK: - AccountConnectionProtocol

    func validateCredentials() async throws {
        // Strangler-fig migration: route ONLY this call through the shared Rust core
        // when the flag is ON. Everything else stays on the Swift SDK.
        if featureFlags.isEnabled(.useRustCoreForAppleApps) {
            let provider = try rustCoreProvider()
            try await callRustCore { try await provider.validate() }
            // The ~87 not-yet-migrated Swift-only fetch methods still depend on
            // `self.provider` and re-call `validateCredentials()` whenever it is nil.
            // Seed it here (no network) so those methods reuse it instead of
            // recursing/re-validating on every call — the runaway validate storm
            // that was triggering the 429 (issue #84).
            try establishSwiftProvider()
            Log.print.info("[Apple] Credentials validated successfully (Rust core)")
            return
        }

        let provider = try createProvider()
        self.provider = provider

        let request = APIEndpoint
            .v1
            .apps
            .get(parameters: .init(limit: 1))

        _ = try await provider.request(request)
        Log.print.info("[Apple] Credentials validated successfully")
    }

    func fetchApps() async throws -> [StackProtocols.AppInfo] {
        // Strangler-fig migration: route ONLY this call through the shared Rust core
        // when the flag is ON. Everything else stays on the Swift SDK.
        if featureFlags.isEnabled(.useRustCoreForAppleApps) {
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

        guard let provider else {
            try await validateCredentials()
            return try await fetchApps()
        }

        let request = APIEndpoint
            .v1
            .apps
            .get(parameters: .init(sort: [.minusname], limit: 200))

        let response = try await provider.request(request)

        let apps = response.data.map { app in
            StackProtocols.AppInfo(
                id: app.id,
                name: app.attributes?.name ?? "",
                bundleId: app.attributes?.bundleID ?? "",
                platform: nil
            )
        }

        Log.print.info("[Apple] Fetched \(apps.count) apps")
        return apps
    }

    func syncApps(accountId: String, store: BlobStore) async throws -> [StackProtocols.AppInfo] {
        // Strangler-fig migration: when the flag is ON, route through the shared
        // Rust core `SyncService`, which fetches the apps AND persists each as a
        // base AppModel blob into `store` (the adapter merges to preserve
        // enrichment/user fields). When OFF this is byte-identical to `fetchApps()`
        // and `store` is unused.
        if featureFlags.isEnabled(.useRustCoreForAppleApps) {
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

        return try await fetchApps()
    }

    func fetchIconUrl(appId: String) async -> String? {
        guard let provider else { return nil }

        do {
            let request = APIEndpoint
                .v1
                .builds
                .get(
                    parameters: .init(
                        filterApp: [appId],
                        sort: [.minusuploadedDate],
                        limit: 1
                    )
                )

            let response = try await provider.request(request)
            guard let build = response.data.first else { return nil }
            return build.attributes?.iconAssetToken?.toIconUrl()
        } catch {
            Log.print.info("[Apple] Icon fetch failed for app \(appId): \(error.localizedDescription)")
            return nil
        }
    }

    func fetchAppStoreVersions(appId: String, limit: Int = 20) async throws -> [AppStoreVersionModel] {
        // Strangler-fig migration: route this read through the shared Rust core when
        // the flag is ON. The Swift-SDK body below is left untouched for the OFF path.
        if featureFlags.isEnabled(.useRustCoreForAppleApps) {
            let provider = try rustCoreProvider()
            guard let versions = provider.appStoreVersions() else {
                throw translate(.Unsupported(message: "App Store Versions capability is not available for this provider."))
            }
            let core = try await callRustCore { try await versions.fetchVersions(appId: appId, limit: UInt32(limit)) }
            let models = core.map { Self.mapVersionInfo($0) }
            Log.print.info("[Apple] Fetched \(models.count) versions (Rust core)")
            return models
        }

        guard let provider else {
            try await validateCredentials()
            return try await fetchAppStoreVersions(appId: appId, limit: limit)
        }

        let request = APIEndpoint
            .v1
            .apps
            .id(appId)
            .appStoreVersions
            .get(parameters: .init(limit: limit))

        let response = try await provider.request(request)

        return response.data.map { version in
            Self.mapVersion(version, appId: appId)
        }
    }

    func createAppStoreVersion(request: CreateAppVersionRequest) async throws -> AppStoreVersionModel {
        // Strangler-fig migration: route this write through the shared Rust core when
        // the flag is ON. The Swift-SDK body below is left untouched for the OFF path.
        if featureFlags.isEnabled(.useRustCoreForAppleApps) {
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

        guard let provider else {
            try await validateCredentials()
            return try await createAppStoreVersion(request: request)
        }

        let body = request.toSDKRequest()
        let endpoint = APIEndpoint.v1.appStoreVersions.post(body)
        let response = try await provider.request(endpoint)
        return Self.mapVersion(response.data, appId: request.appId)
    }

    func fetchAppStoreVersion(appId: String) async throws -> (state: String?, version: String?) {
        // Strangler-fig migration: route this read through the shared Rust core when
        // the flag is ON. The core returns raw state/version strings — exactly what
        // this lightweight accessor wants. The Swift-SDK body below is the OFF path.
        if featureFlags.isEnabled(.useRustCoreForAppleApps) {
            let provider = try rustCoreProvider()
            guard let versions = provider.appStoreVersions() else {
                throw translate(.Unsupported(message: "App Store Versions capability is not available for this provider."))
            }
            let core = try await callRustCore { try await versions.fetchVersions(appId: appId, limit: 1) }
            guard let first = core.first else { return (nil, nil) }
            return (first.appStoreState, first.versionString)
        }

        guard let provider else { return (nil, nil) }

        do {
            let request = APIEndpoint
                .v1
                .apps
                .id(appId)
                .appStoreVersions
                .get(parameters: .init(limit: 1))

            let response = try await provider.request(request)
            guard let version = response.data.first else { return (nil, nil) }
            return (
                version.attributes?.appStoreState?.rawValue,
                version.attributes?.versionString
            )
        } catch {
            Log.print.info("[Apple] Version fetch failed for app \(appId): \(error.localizedDescription)")
            return (nil, nil)
        }
    }

    // MARK: - Delete Version

    func deleteAppStoreVersion(id: String) async throws {
        // Strangler-fig migration: route this write through the shared Rust core when
        // the flag is ON. The Swift-SDK body below is left untouched for the OFF path.
        if featureFlags.isEnabled(.useRustCoreForAppleApps) {
            let provider = try rustCoreProvider()
            guard let versions = provider.appStoreVersions() else {
                throw translate(.Unsupported(message: "App Store Versions capability is not available for this provider."))
            }
            try await callRustCore { try await versions.deleteVersion(id: id) }
            Log.print.info("[Apple] Deleted version \(id) (Rust core)")
            return
        }

        guard let provider else {
            try await validateCredentials()
            return try await deleteAppStoreVersion(id: id)
        }

        let endpoint = APIEndpoint.v1.appStoreVersions.id(id).delete
        _ = try await provider.request(endpoint)
        Log.print.info("[Apple] Deleted version \(id)")
    }

    // MARK: - Update Version

    func updateAppStoreVersion(
        id: String,
        versionString: String? = nil,
        copyright: String? = nil,
        releaseType: AppStoreVersionUpdateRequest.Data.Attributes.ReleaseType? = nil,
        earliestReleaseDate: Date? = nil
    ) async throws {
        // Strangler-fig migration: route this write through the shared Rust core when
        // the flag is ON. The core passes `earliestReleaseDate` through verbatim, so we
        // format the `Date?` as ISO8601 here. The Swift-SDK body below is the OFF path.
        if featureFlags.isEnabled(.useRustCoreForAppleApps) {
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
                    releaseType: releaseType?.rawValue,
                    earliestReleaseDate: earliestISO
                )
            }
            Log.print.info("[Apple] Updated version \(id) (Rust core)")
            return
        }

        guard let provider else {
            try await validateCredentials()
            return try await updateAppStoreVersion(id: id, versionString: versionString, copyright: copyright, releaseType: releaseType, earliestReleaseDate: earliestReleaseDate)
        }

        let body = AppStoreVersionUpdateRequest(
            data: .init(
                type: .appStoreVersions,
                id: id,
                attributes: .init(
                    versionString: versionString,
                    copyright: copyright,
                    releaseType: releaseType,
                    earliestReleaseDate: earliestReleaseDate
                )
            )
        )

        let endpoint = APIEndpoint.v1.appStoreVersions.id(id).patch(body)
        _ = try await provider.request(endpoint)
        Log.print.info("[Apple] Updated version \(id)")
    }

    // MARK: - Localizations

    func fetchLocalizations(versionId: String) async throws -> [AppStoreLocalizationModel] {
        guard let provider else {
            try await validateCredentials()
            return try await fetchLocalizations(versionId: versionId)
        }

        let endpoint = APIEndpoint
            .v1
            .appStoreVersions
            .id(versionId)
            .appStoreVersionLocalizations
            .get()

        let response = try await provider.request(endpoint)

        return response.data.map { loc in
            AppStoreLocalizationModel(
                id: loc.id,
                locale: loc.attributes?.locale,
                description: loc.attributes?.description,
                keywords: loc.attributes?.keywords,
                promotionalText: loc.attributes?.promotionalText,
                supportUrl: loc.attributes?.supportURL?.absoluteString,
                marketingUrl: loc.attributes?.marketingURL?.absoluteString,
                whatsNew: loc.attributes?.whatsNew
            )
        }
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
        guard let provider else {
            try await validateCredentials()
            return try await updateLocalization(id: id, description: description, keywords: keywords, promotionalText: promotionalText, supportUrl: supportUrl, marketingUrl: marketingUrl, whatsNew: whatsNew)
        }

        let body = AppStoreVersionLocalizationUpdateRequest(
            data: .init(
                type: .appStoreVersionLocalizations,
                id: id,
                attributes: .init(
                    description: description,
                    keywords: keywords,
                    marketingURL: marketingUrl.flatMap { URL(string: $0) },
                    promotionalText: promotionalText,
                    supportURL: supportUrl.flatMap { URL(string: $0) },
                    whatsNew: whatsNew
                )
            )
        )

        let endpoint = APIEndpoint.v1.appStoreVersionLocalizations.id(id).patch(body)
        _ = try await provider.request(endpoint)
        Log.print.info("[Apple] Updated localization \(id)")
    }

    // MARK: - Builds

    func fetchBuilds(appId: String, limit: Int = 50) async throws -> [BuildModel] {
        // Strangler-fig migration: route this eager-list read through the shared Rust
        // core when the flag is ON. The Swift-SDK body below is left untouched for the
        // OFF path.
        if featureFlags.isEnabled(.useRustCoreForAppleApps) {
            let provider = try rustCoreProvider()
            guard let builds = provider.builds() else {
                throw translate(.Unsupported(message: "Builds capability is not available for this provider."))
            }
            let core = try await callRustCore { try await builds.fetchBuilds(appId: appId, limit: UInt32(limit)) }
            let models = core.map { Self.mapBuildInfo($0) }
            Log.print.info("[Apple] Fetched \(models.count) builds (Rust core)")
            return models
        }

        guard let provider else {
            try await validateCredentials()
            return try await fetchBuilds(appId: appId, limit: limit)
        }

        let request = APIEndpoint
            .v1
            .builds
            .get(
                parameters: .init(
                    filterApp: [appId],
                    sort: [.minusuploadedDate],
                    limit: limit,
                    include: [.preReleaseVersion, .buildBetaDetail, .betaAppReviewSubmission]
                )
            )

        let response = try await provider.request(request)
        return mapBuilds(response)
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
        if featureFlags.isEnabled(.useRustCoreForAppleApps) {
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

        guard let provider else {
            try await validateCredentials()
            return try await fetchBuildsPage(appId: appId, platform: platform, processingStates: processingStates, limit: limit, pageAfterResponse: pageAfterResponse)
        }

        typealias Params = APIEndpoint.V1.Builds.GetParameters

        let platformFilter: [Params.FilterPreReleaseVersionPlatform]? = platform
            .flatMap { Params.FilterPreReleaseVersionPlatform(rawValue: $0) }
            .map { [$0] }

        let stateFilter: [Params.FilterProcessingState]? = processingStates.flatMap { raws in
            let mapped = raws.compactMap { Params.FilterProcessingState(rawValue: $0) }
            return mapped.isEmpty ? nil : mapped
        }

        let endpoint = APIEndpoint
            .v1
            .builds
            .get(
                parameters: .init(
                    filterProcessingState: stateFilter,
                    filterPreReleaseVersionPlatform: platformFilter,
                    filterApp: [appId],
                    sort: [.minusuploadedDate],
                    limit: limit,
                    include: [.preReleaseVersion, .buildBetaDetail, .betaAppReviewSubmission]
                )
            )

        let response: BuildsResponse
        if let previousResponse = pageAfterResponse as? BuildsResponse {
            guard let nextPage = try await provider.request(endpoint, pageAfter: previousResponse) else {
                return BuildsPage(builds: [], hasNextPage: false, rawResponse: nil)
            }
            response = nextPage
        } else {
            response = try await provider.request(endpoint)
        }

        let builds = mapBuilds(response)
        return BuildsPage(builds: builds, hasNextPage: response.links.next != nil, rawResponse: response)
    }

    private func mapBuilds(_ response: BuildsResponse) -> [BuildModel] {
        var platformByPreReleaseId: [String: String] = [:]
        var marketingVersionByPreReleaseId: [String: String] = [:]
        var detailById: [String: BuildBetaDetail] = [:]
        var submissionById: [String: BetaAppReviewSubmission] = [:]

        for item in response.included ?? [] {
            switch item {
            case .prereleaseVersion(let pre):
                if let platform = pre.attributes?.platform?.rawValue {
                    platformByPreReleaseId[pre.id] = platform
                }
                if let version = pre.attributes?.version {
                    marketingVersionByPreReleaseId[pre.id] = version
                }
            case .buildBetaDetail(let detail):
                detailById[detail.id] = detail
            case .betaAppReviewSubmission(let submission):
                submissionById[submission.id] = submission
            default:
                break
            }
        }

        return response.data.map { build in
            let preReleaseId = build.relationships?.preReleaseVersion?.data?.id
            let platform = preReleaseId.flatMap { platformByPreReleaseId[$0] }
            let marketingVersion = preReleaseId.flatMap { marketingVersionByPreReleaseId[$0] }

            let detailId = build.relationships?.buildBetaDetail?.data?.id
            let detail = detailId.flatMap { detailById[$0] }

            let submissionId = build.relationships?.betaAppReviewSubmission?.data?.id
            let submission = submissionId.flatMap { submissionById[$0] }

            return BuildModel(
                id: build.id,
                version: build.attributes?.version,
                marketingVersion: marketingVersion,
                processingState: build.attributes?.processingState?.rawValue,
                uploadedDate: build.attributes?.uploadedDate,
                iconUrl: build.attributes?.iconAssetToken?.toIconUrl(),
                platform: platform,
                externalBuildState: detail?.attributes?.externalBuildState?.rawValue,
                betaReviewState: submission?.attributes?.betaReviewState?.rawValue,
                submittedDate: submission?.attributes?.submittedDate,
                expirationDate: build.attributes?.expirationDate,
                isExpired: build.attributes?.isExpired ?? false,
                minOsVersion: build.attributes?.minOsVersion,
                computedMinMacOsVersion: build.attributes?.computedMinMacOsVersion,
                computedMinVisionOsVersion: build.attributes?.computedMinVisionOsVersion,
                buildAudienceType: build.attributes?.buildAudienceType?.rawValue,
                usesNonExemptEncryption: build.attributes?.usesNonExemptEncryption,
                internalBuildState: detail?.attributes?.internalBuildState?.rawValue,
                autoNotifyEnabled: detail?.attributes?.isAutoNotifyEnabled
            )
        }
    }

    func fetchBuildDetail(buildId: String) async throws -> BuildDetailData {
        if featureFlags.isEnabled(.useRustCoreForAppleApps) {
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

        guard let provider else {
            try await validateCredentials()
            return try await fetchBuildDetail(buildId: buildId)
        }

        let endpoint = APIEndpoint.v1.builds.id(buildId).get(
            parameters: .init(
                include: [.preReleaseVersion, .buildBetaDetail, .betaAppReviewSubmission, .betaGroups, .betaBuildLocalizations],
                limitBetaBuildLocalizations: 50,
                limitBetaGroups: 50
            )
        )
        let response = try await provider.request(endpoint)
        let b = response.data

        var marketingVersion: String?
        var platform: String?
        var detail: BuildBetaDetail?
        var submission: BetaAppReviewSubmission?
        var groups: [BetaGroupModel] = []
        var localizations: [BetaBuildLocalizationModel] = []

        for item in response.included ?? [] {
            switch item {
            case .prereleaseVersion(let pre):
                marketingVersion = pre.attributes?.version
                platform = pre.attributes?.platform?.rawValue
            case .buildBetaDetail(let d):
                detail = d
            case .betaAppReviewSubmission(let s):
                submission = s
            case .betaGroup(let g):
                groups.append(
                    BetaGroupModel(
                        id: g.id,
                        name: g.attributes?.name ?? "",
                        isInternalGroup: g.attributes?.isInternalGroup ?? false,
                        createdDate: g.attributes?.createdDate,
                        hasAccessToAllBuilds: g.attributes?.hasAccessToAllBuilds ?? false,
                        isPublicLinkEnabled: g.attributes?.isPublicLinkEnabled ?? false,
                        publicLink: g.attributes?.publicLink,
                        publicLinkId: g.attributes?.publicLinkID,
                        publicLinkLimit: g.attributes?.publicLinkLimit,
                        isPublicLinkLimitEnabled: g.attributes?.isPublicLinkLimitEnabled ?? false,
                        isFeedbackEnabled: g.attributes?.isFeedbackEnabled ?? false,
                        testerCount: nil,
                        buildCount: nil
                    )
                )
            case .betaBuildLocalization(let l):
                localizations.append(
                    BetaBuildLocalizationModel(
                        id: l.id,
                        locale: l.attributes?.locale ?? "",
                        whatsNew: l.attributes?.whatsNew
                    )
                )
            default:
                break
            }
        }

        let build = BuildModel(
            id: b.id,
            version: b.attributes?.version,
            marketingVersion: marketingVersion,
            processingState: b.attributes?.processingState?.rawValue,
            uploadedDate: b.attributes?.uploadedDate,
            iconUrl: b.attributes?.iconAssetToken?.toIconUrl(),
            platform: platform,
            externalBuildState: detail?.attributes?.externalBuildState?.rawValue,
            betaReviewState: submission?.attributes?.betaReviewState?.rawValue,
            submittedDate: submission?.attributes?.submittedDate,
            expirationDate: b.attributes?.expirationDate,
            isExpired: b.attributes?.isExpired ?? false,
            minOsVersion: b.attributes?.minOsVersion,
            computedMinMacOsVersion: b.attributes?.computedMinMacOsVersion,
            computedMinVisionOsVersion: b.attributes?.computedMinVisionOsVersion,
            buildAudienceType: b.attributes?.buildAudienceType?.rawValue,
            usesNonExemptEncryption: b.attributes?.usesNonExemptEncryption,
            internalBuildState: detail?.attributes?.internalBuildState?.rawValue,
            autoNotifyEnabled: detail?.attributes?.isAutoNotifyEnabled
        )

        return BuildDetailData(build: build, betaGroups: groups, localizations: localizations)
    }

    func expireBuild(buildId: String) async throws {
        // Strangler-fig migration: route this write through the shared Rust core
        // when the flag is ON; the Swift-SDK body below is the flag-OFF fallthrough.
        if featureFlags.isEnabled(.useRustCoreForAppleApps) {
            let provider = try rustCoreProvider()
            guard let builds = provider.builds() else {
                throw translate(.Unsupported(message: "Builds capability is not available for this provider."))
            }
            try await callRustCore { try await builds.expireBuild(buildId: buildId) }
            Log.print.info("[Apple] Expired build \(buildId) (Rust core)")
            return
        }

        guard let provider else {
            try await validateCredentials()
            return try await expireBuild(buildId: buildId)
        }

        let body = BuildUpdateRequest(
            data: .init(
                type: .builds,
                id: buildId,
                attributes: .init(isExpired: true)
            )
        )
        let endpoint = APIEndpoint.v1.builds.id(buildId).patch(body)
        _ = try await provider.request(endpoint)
        Log.print.info("[Apple] Expired build \(buildId)")
    }

    func fetchCurrentBuild(versionId: String) async throws -> BuildModel? {
        if featureFlags.isEnabled(.useRustCoreForAppleApps) {
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

        guard let provider else {
            try await validateCredentials()
            return try await fetchCurrentBuild(versionId: versionId)
        }

        do {
            let endpoint = APIEndpoint
                .v1
                .appStoreVersions
                .id(versionId)
                .build
                .get(fieldsBuilds: [])

            let build = try await provider.request(endpoint).data
            return BuildModel(
                id: build.id,
                version: build.attributes?.version,
                processingState: build.attributes?.processingState?.rawValue,
                uploadedDate: build.attributes?.uploadedDate,
                iconUrl: build.attributes?.iconAssetToken?.toIconUrl()
            )
        } catch {
            Log.print.info("[Apple] No build attached to version \(versionId)")
            return nil
        }
    }

    func attachBuild(versionId: String, buildId: String) async throws {
        // Strangler-fig migration: route this write through the shared Rust core
        // when the flag is ON; the Swift-SDK body below is the flag-OFF fallthrough.
        if featureFlags.isEnabled(.useRustCoreForAppleApps) {
            let provider = try rustCoreProvider()
            guard let builds = provider.builds() else {
                throw translate(.Unsupported(message: "Builds capability is not available for this provider."))
            }
            try await callRustCore { try await builds.attachBuild(versionId: versionId, buildId: buildId) }
            Log.print.info("[Apple] Attached build \(buildId) to version \(versionId) (Rust core)")
            return
        }

        guard let provider else {
            try await validateCredentials()
            return try await attachBuild(versionId: versionId, buildId: buildId)
        }

        let body = AppStoreVersionBuildLinkageRequest(
            data: .init(type: .builds, id: buildId)
        )

        let endpoint = APIEndpoint
            .v1
            .appStoreVersions
            .id(versionId)
            .relationships
            .build
            .patch(body)

        _ = try await provider.request(endpoint)
        Log.print.info("[Apple] Attached build \(buildId) to version \(versionId)")
    }

    // MARK: - Review Submissions

    func fetchReviewSubmissions(appId: String) async throws -> [ReviewSubmissionModel] {
        // Strangler-fig migration: route ONLY this read through the shared Rust core
        // when the flag is ON. Everything else (customer-reviews paging, submit/cancel)
        // stays on the Swift SDK.
        if featureFlags.isEnabled(.useRustCoreForAppleApps) {
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

        guard let provider else {
            try await validateCredentials()
            return try await fetchReviewSubmissions(appId: appId)
        }

        let endpoint = APIEndpoint.v1.reviewSubmissions.get(
            parameters: .init(
                filterApp: [appId],
                limit: 50,
                include: [.appStoreVersionForReview, .submittedByActor]
            )
        )

        let response = try await provider.request(endpoint)

        let models: [ReviewSubmissionModel] = response.data.map { submission in
            let versionId = submission.relationships?.appStoreVersionForReview?.data?.id
            let actorId = submission.relationships?.submittedByActor?.data?.id

            var versionString: String?
            if let versionId {
                versionString = response.included?.compactMap { item -> String? in
                    guard case .appStoreVersion(let v) = item, v.id == versionId else { return nil }
                    return v.attributes?.versionString
                }.first
            }

            var actorName: String?
            var actorEmail: String?
            if let actorId {
                let actor = response.included?.compactMap { item -> Actor? in
                    guard case .actor(let a) = item, a.id == actorId else { return nil }
                    return a
                }.first

                if let a = actor {
                    if let first = a.attributes?.userFirstName, let last = a.attributes?.userLastName {
                        actorName = "\(first) \(last)"
                    } else if let apiKey = a.attributes?.apiKeyID {
                        actorName = "API Key (\(apiKey))"
                    } else if a.attributes?.actorType == .apple {
                        actorName = "Apple"
                    }
                    actorEmail = a.attributes?.userEmail
                }
            }

            return ReviewSubmissionModel(
                id: submission.id,
                appId: appId,
                platform: submission.attributes?.platform?.rawValue,
                submittedDate: submission.attributes?.submittedDate,
                state: submission.attributes?.state?.rawValue,
                versionString: versionString,
                versionId: versionId,
                submittedByName: actorName,
                submittedByEmail: actorEmail
            )
        }

        return models.sorted { ($0.submittedDate ?? .distantPast) > ($1.submittedDate ?? .distantPast) }
    }

    // MARK: - TestFlight: Beta Groups

    func fetchBetaGroups(appId: String) async throws -> [BetaGroupModel] {
        // Strangler-fig migration: route ONLY this read through the shared Rust core
        // when the flag is ON. The create/update/delete and tester management below
        // stay on the Swift SDK this batch.
        if featureFlags.isEnabled(.useRustCoreForAppleApps) {
            let provider = try rustCoreProvider()
            guard let bg = provider.betaGroups() else {
                throw translate(.Unsupported(message: "Beta Groups capability is not available for this provider."))
            }
            let core = try await callRustCore { try await bg.fetchBetaGroups(appId: appId, limit: 50) }
            let models = core.map { Self.mapBetaGroupInfo($0) }
            Log.print.info("[Apple] Fetched \(models.count) beta groups (Rust core)")
            return models
        }

        guard let provider else {
            try await validateCredentials()
            return try await fetchBetaGroups(appId: appId)
        }

        let endpoint = APIEndpoint.v1.apps.id(appId).betaGroups.get(limit: 50)
        let response = try await provider.request(endpoint)

        return response.data.map { group in
            BetaGroupModel(
                id: group.id,
                name: group.attributes?.name ?? "",
                isInternalGroup: group.attributes?.isInternalGroup ?? false,
                createdDate: group.attributes?.createdDate,
                hasAccessToAllBuilds: group.attributes?.hasAccessToAllBuilds ?? false,
                isPublicLinkEnabled: group.attributes?.isPublicLinkEnabled ?? false,
                publicLink: group.attributes?.publicLink,
                publicLinkId: group.attributes?.publicLinkID,
                publicLinkLimit: group.attributes?.publicLinkLimit,
                isPublicLinkLimitEnabled: group.attributes?.isPublicLinkLimitEnabled ?? false,
                isFeedbackEnabled: group.attributes?.isFeedbackEnabled ?? false,
                testerCount: group.relationships?.betaTesters?.meta?.paging.total,
                buildCount: group.relationships?.builds?.meta?.paging.total
            )
        }
    }

    func createBetaGroup(
        appId: String,
        name: String,
        isInternal: Bool,
        isPublicLinkEnabled: Bool = false,
        hasAccessToAllBuilds: Bool = false
    ) async throws -> BetaGroupModel {
        // Strangler-fig migration: route this write through the shared Rust core
        // when the flag is ON; the Swift-SDK body below is the flag-OFF fallthrough.
        if featureFlags.isEnabled(.useRustCoreForAppleApps) {
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

        guard let provider else {
            try await validateCredentials()
            return try await createBetaGroup(
                appId: appId,
                name: name,
                isInternal: isInternal,
                isPublicLinkEnabled: isPublicLinkEnabled,
                hasAccessToAllBuilds: hasAccessToAllBuilds
            )
        }

        let body = BetaGroupCreateRequest(
            data: .init(
                type: .betaGroups,
                attributes: .init(
                    name: name,
                    isInternalGroup: isInternal,
                    hasAccessToAllBuilds: hasAccessToAllBuilds,
                    isPublicLinkEnabled: isPublicLinkEnabled,
                    isFeedbackEnabled: true
                ),
                relationships: .init(
                    app: .init(data: .init(type: .apps, id: appId))
                )
            )
        )

        let endpoint = APIEndpoint.v1.betaGroups.post(body)
        let response = try await provider.request(endpoint)
        let g = response.data

        Log.print.info("[TestFlight] Created beta group: \(name)")
        return BetaGroupModel(
            id: g.id,
            name: g.attributes?.name ?? name,
            isInternalGroup: g.attributes?.isInternalGroup ?? isInternal,
            createdDate: g.attributes?.createdDate,
            hasAccessToAllBuilds: g.attributes?.hasAccessToAllBuilds ?? false,
            isPublicLinkEnabled: g.attributes?.isPublicLinkEnabled ?? false,
            publicLink: g.attributes?.publicLink,
            publicLinkId: g.attributes?.publicLinkID,
            publicLinkLimit: g.attributes?.publicLinkLimit,
            isPublicLinkLimitEnabled: g.attributes?.isPublicLinkLimitEnabled ?? false,
            isFeedbackEnabled: g.attributes?.isFeedbackEnabled ?? false,
            testerCount: 0,
            buildCount: 0
        )
    }

    func updateBetaGroup(id: String, name: String?, isPublicLinkEnabled: Bool?, publicLinkLimit: Int?, isFeedbackEnabled: Bool?) async throws {
        // Strangler-fig migration: route this write through the shared Rust core
        // when the flag is ON; the Swift-SDK body below is the flag-OFF fallthrough.
        if featureFlags.isEnabled(.useRustCoreForAppleApps) {
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

        guard let provider else {
            try await validateCredentials()
            return try await updateBetaGroup(id: id, name: name, isPublicLinkEnabled: isPublicLinkEnabled, publicLinkLimit: publicLinkLimit, isFeedbackEnabled: isFeedbackEnabled)
        }

        let body = BetaGroupUpdateRequest(
            data: .init(
                type: .betaGroups,
                id: id,
                attributes: .init(
                    name: name,
                    isPublicLinkEnabled: isPublicLinkEnabled,
                    publicLinkLimit: publicLinkLimit,
                    isFeedbackEnabled: isFeedbackEnabled
                )
            )
        )

        let endpoint = APIEndpoint.v1.betaGroups.id(id).patch(body)
        _ = try await provider.request(endpoint)
        Log.print.info("[TestFlight] Updated beta group \(id)")
    }

    func deleteBetaGroup(id: String) async throws {
        // Strangler-fig migration: route this write through the shared Rust core
        // when the flag is ON; the Swift-SDK body below is the flag-OFF fallthrough.
        if featureFlags.isEnabled(.useRustCoreForAppleApps) {
            let provider = try rustCoreProvider()
            guard let bg = provider.betaGroups() else {
                throw translate(.Unsupported(message: "Beta Groups capability is not available for this provider."))
            }
            try await callRustCore { try await bg.deleteBetaGroup(groupId: id) }
            Log.print.info("[Apple] Deleted beta group \(id) (Rust core)")
            return
        }

        guard let provider else {
            try await validateCredentials()
            return try await deleteBetaGroup(id: id)
        }

        let endpoint = APIEndpoint.v1.betaGroups.id(id).delete
        _ = try await provider.request(endpoint)
        Log.print.info("[TestFlight] Deleted beta group \(id)")
    }

    // MARK: - TestFlight: Beta Testers

    func fetchTesterCount(groupId: String) async throws -> Int {
        // Strangler-fig migration: route this read through the shared Rust core
        // when the flag is ON; the Swift-SDK body below is the flag-OFF fallthrough.
        if featureFlags.isEnabled(.useRustCoreForAppleApps) {
            let provider = try rustCoreProvider()
            guard let bg = provider.betaGroups() else {
                throw translate(.Unsupported(message: "Beta Groups capability is not available for this provider."))
            }
            let count = try await callRustCore { try await bg.fetchTesterCount(groupId: groupId) }
            Log.print.info("[Apple] Fetched tester count \(count) for group \(groupId) (Rust core)")
            return Int(count)
        }

        guard let provider else {
            try await validateCredentials()
            return try await fetchTesterCount(groupId: groupId)
        }

        let endpoint = APIEndpoint.v1.betaGroups.id(groupId).betaTesters.get(fieldsBetaTesters: [], limit: 1)
        let response = try await provider.request(endpoint)
        return response.meta?.paging.total ?? 0
    }

    func fetchBetaTestersForGroup(groupId: String) async throws -> [BetaTesterModel] {
        // Strangler-fig migration: route ONLY this read through the shared Rust core
        // when the flag is ON. Add/remove tester and the tester count below stay on
        // the Swift SDK this batch.
        if featureFlags.isEnabled(.useRustCoreForAppleApps) {
            let provider = try rustCoreProvider()
            guard let bg = provider.betaGroups() else {
                throw translate(.Unsupported(message: "Beta Groups capability is not available for this provider."))
            }
            let core = try await callRustCore { try await bg.fetchBetaTesters(groupId: groupId, limit: 200) }
            let models = core.map { Self.mapBetaTesterInfo($0) }
            Log.print.info("[Apple] Fetched \(models.count) beta testers (Rust core)")
            return models
        }

        guard let provider else {
            try await validateCredentials()
            return try await fetchBetaTestersForGroup(groupId: groupId)
        }

        let endpoint = APIEndpoint.v1.betaGroups.id(groupId).betaTesters.get(fieldsBetaTesters: nil, limit: 200)
        let response = try await provider.request(endpoint)

        return response.data.map { tester in
            BetaTesterModel(
                id: tester.id,
                firstName: tester.attributes?.firstName,
                lastName: tester.attributes?.lastName,
                email: tester.attributes?.email,
                inviteType: tester.attributes?.inviteType?.rawValue,
                state: tester.attributes?.state?.rawValue
            )
        }
    }

    func addTesterToGroup(email: String, firstName: String?, lastName: String?, groupId: String) async throws {
        // Strangler-fig migration: route this write through the shared Rust core
        // when the flag is ON; the Swift-SDK body below is the flag-OFF fallthrough.
        if featureFlags.isEnabled(.useRustCoreForAppleApps) {
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

        guard let provider else {
            try await validateCredentials()
            return try await addTesterToGroup(email: email, firstName: firstName, lastName: lastName, groupId: groupId)
        }

        let body = BetaTesterCreateRequest(
            data: .init(
                type: .betaTesters,
                attributes: .init(firstName: firstName, lastName: lastName, email: email),
                relationships: .init(
                    betaGroups: .init(data: [.init(type: .betaGroups, id: groupId)])
                )
            )
        )

        let endpoint = APIEndpoint.v1.betaTesters.post(body)
        _ = try await provider.request(endpoint)
        Log.print.info("[TestFlight] Added tester \(email) to group \(groupId)")
    }

    func removeTesterFromGroup(testerId: String, groupId: String) async throws {
        // Strangler-fig migration: route this write through the shared Rust core
        // when the flag is ON; the Swift-SDK body below is the flag-OFF fallthrough.
        if featureFlags.isEnabled(.useRustCoreForAppleApps) {
            let provider = try rustCoreProvider()
            guard let bg = provider.betaGroups() else {
                throw translate(.Unsupported(message: "Beta Groups capability is not available for this provider."))
            }
            try await callRustCore { try await bg.removeBetaTester(groupId: groupId, testerId: testerId) }
            Log.print.info("[Apple] Removed tester \(testerId) from group \(groupId) (Rust core)")
            return
        }

        guard let provider else {
            try await validateCredentials()
            return try await removeTesterFromGroup(testerId: testerId, groupId: groupId)
        }

        let body = BetaGroupBetaTestersLinkagesRequest(
            data: [.init(type: .betaTesters, id: testerId)]
        )

        let endpoint = APIEndpoint.v1.betaGroups.id(groupId).relationships.betaTesters.delete(body)
        _ = try await provider.request(endpoint)
        Log.print.info("[TestFlight] Removed tester \(testerId) from group \(groupId)")
    }

    func resendInvite(testerId: String, appId: String) async throws {
        // Strangler-fig migration: route this write through the shared Rust core
        // when the flag is ON; the Swift-SDK body below is the flag-OFF fallthrough.
        if featureFlags.isEnabled(.useRustCoreForAppleApps) {
            let provider = try rustCoreProvider()
            guard let bg = provider.betaGroups() else {
                throw translate(.Unsupported(message: "Beta Groups capability is not available for this provider."))
            }
            try await callRustCore { try await bg.resendInvite(testerId: testerId, appId: appId) }
            Log.print.info("[Apple] Resent invite to tester \(testerId) (Rust core)")
            return
        }

        guard let provider else {
            try await validateCredentials()
            return try await resendInvite(testerId: testerId, appId: appId)
        }

        let body = BetaTesterInvitationCreateRequest(
            data: .init(
                type: .betaTesterInvitations,
                relationships: .init(
                    betaTester: .init(data: .init(type: .betaTesters, id: testerId)),
                    app: .init(data: .init(type: .apps, id: appId))
                )
            )
        )

        let endpoint = APIEndpoint.v1.betaTesterInvitations.post(body)
        _ = try await provider.request(endpoint)
        Log.print.info("[TestFlight] Resent invite to tester \(testerId)")
    }

    // MARK: - Team Members

    func fetchTeamMembers() async throws -> [TeamMemberModel] {
        guard let provider else {
            try await validateCredentials()
            return try await fetchTeamMembers()
        }

        let endpoint = APIEndpoint.v1.users.get(
            parameters: .init(
                fieldsUsers: [.firstName, .lastName, .username, .roles],
                limit: 200
            )
        )
        let response = try await provider.request(endpoint)
        Log.print.info("[Apple] Fetched \(response.data.count) team members")
        return response.data.map { user in
            TeamMemberModel(
                id: user.id,
                firstName: user.attributes?.firstName,
                lastName: user.attributes?.lastName,
                username: user.attributes?.username,
                roles: user.attributes?.roles?.map(\.rawValue) ?? []
            )
        }
    }

    // MARK: - User Management

    func fetchUsers() async throws -> [UserModel] {
        guard let provider else {
            try await validateCredentials()
            return try await fetchUsers()
        }

        async let activeResponse = provider.request(
            APIEndpoint.v1.users.get(
                parameters: .init(
                    fieldsUsers: [.firstName, .lastName, .username, .roles, .allAppsVisible, .provisioningAllowed],
                    limit: 200
                )
            )
        )

        async let pendingResponse = provider.request(
            APIEndpoint.v1.userInvitations.get(
                parameters: .init(
                    fieldsUserInvitations: [.firstName, .lastName, .email, .roles, .allAppsVisible, .provisioningAllowed, .expirationDate],
                    limit: 200
                )
            )
        )

        let active = try await activeResponse
        let pending = try await pendingResponse

        let activeUsers: [UserModel] = active.data.map { user in
            UserModel(
                id: user.id,
                firstName: user.attributes?.firstName,
                lastName: user.attributes?.lastName,
                email: user.attributes?.username,
                roles: user.attributes?.roles?.map(\.rawValue) ?? [],
                allAppsVisible: user.attributes?.isAllAppsVisible ?? false,
                provisioningAllowed: user.attributes?.isProvisioningAllowed ?? false,
                isPending: false,
                expirationDate: nil
            )
        }

        let pendingUsers: [UserModel] = pending.data.map { inv in
            UserModel(
                id: inv.id,
                firstName: inv.attributes?.firstName,
                lastName: inv.attributes?.lastName,
                email: inv.attributes?.email,
                roles: inv.attributes?.roles?.map(\.rawValue) ?? [],
                allAppsVisible: inv.attributes?.isAllAppsVisible ?? false,
                provisioningAllowed: inv.attributes?.isProvisioningAllowed ?? false,
                isPending: true,
                expirationDate: inv.attributes?.expirationDate
            )
        }

        Log.print.info("[Apple] Fetched \(activeUsers.count) users + \(pendingUsers.count) pending invitations")
        return activeUsers + pendingUsers
    }

    func inviteUser(
        email: String,
        firstName: String,
        lastName: String,
        roles: [String],
        allAppsVisible: Bool,
        provisioningAllowed: Bool
    ) async throws {
        guard let provider else {
            try await validateCredentials()
            return try await inviteUser(
                email: email, firstName: firstName, lastName: lastName,
                roles: roles, allAppsVisible: allAppsVisible, provisioningAllowed: provisioningAllowed
            )
        }

        let userRoles: [UserRole] = roles.compactMap { UserRole(rawValue: $0) }

        let body = UserInvitationCreateRequest(
            data: .init(
                type: .userInvitations,
                attributes: .init(
                    email: email,
                    firstName: firstName,
                    lastName: lastName,
                    roles: userRoles,
                    isAllAppsVisible: allAppsVisible,
                    isProvisioningAllowed: provisioningAllowed
                )
            )
        )

        let endpoint = APIEndpoint.v1.userInvitations.post(body)
        _ = try await provider.request(endpoint)
        Log.print.info("[Apple] Invited user \(email)")
    }

    func deleteUser(id: String, isPending: Bool) async throws {
        guard let provider else {
            try await validateCredentials()
            return try await deleteUser(id: id, isPending: isPending)
        }

        if isPending {
            let endpoint = APIEndpoint.v1.userInvitations.id(id).delete
            _ = try await provider.request(endpoint)
            Log.print.info("[Apple] Cancelled invitation \(id)")
        } else {
            let endpoint = APIEndpoint.v1.users.id(id).delete
            _ = try await provider.request(endpoint)
            Log.print.info("[Apple] Deleted user \(id)")
        }
    }

    // MARK: - TestFlight: Builds for Group

    func fetchBuildsForGroup(groupId: String) async throws -> [BuildModel] {
        if featureFlags.isEnabled(.useRustCoreForAppleApps) {
            let provider = try rustCoreProvider()
            guard let builds = provider.builds() else {
                throw translate(.Unsupported(message: "Builds capability is not available for this provider."))
            }
            let core = try await callRustCore { try await builds.fetchBuildsForGroup(groupId: groupId, limit: 200) }
            let models = core.map { Self.mapBuildInfo($0) }
            Log.print.info("[TestFlight] Fetched \(models.count) builds for group \(groupId) (Rust core)")
            return models
        }

        guard let provider else {
            try await validateCredentials()
            return try await fetchBuildsForGroup(groupId: groupId)
        }

        let endpoint = APIEndpoint
            .v1
            .builds
            .get(
                parameters: .init(
                    filterBetaGroups: [groupId],
                    sort: [.minusuploadedDate],
                    limit: 200,
                    include: [.preReleaseVersion, .buildBetaDetail, .betaAppReviewSubmission]
                )
            )

        let response = try await provider.request(endpoint)
        return mapBuilds(response)
    }

    // MARK: - TestFlight: Beta Review Submission

    func submitBuildForBetaReview(buildId: String) async throws {
        // Strangler-fig migration: route this write through the shared Rust core
        // when the flag is ON; the Swift-SDK body below is the flag-OFF fallthrough.
        if featureFlags.isEnabled(.useRustCoreForAppleApps) {
            let provider = try rustCoreProvider()
            guard let builds = provider.builds() else {
                throw translate(.Unsupported(message: "Builds capability is not available for this provider."))
            }
            try await callRustCore { try await builds.submitBuildForBetaReview(buildId: buildId) }
            Log.print.info("[TestFlight] Submitted build \(buildId) for beta review (Rust core)")
            return
        }

        guard let provider else {
            try await validateCredentials()
            return try await submitBuildForBetaReview(buildId: buildId)
        }

        let body = BetaAppReviewSubmissionCreateRequest(
            data: .init(
                type: .betaAppReviewSubmissions,
                relationships: .init(
                    build: .init(data: .init(type: .builds, id: buildId))
                )
            )
        )

        let endpoint = APIEndpoint.v1.betaAppReviewSubmissions.post(body)
        _ = try await provider.request(endpoint)
        Log.print.info("[TestFlight] Submitted build \(buildId) for beta review")
    }

    func fetchBetaBuildLocalizations(buildId: String) async throws -> [BetaBuildLocalizationModel] {
        // Strangler-fig migration: route this read through the shared Rust core
        // when the flag is ON; the Swift-SDK body below is the flag-OFF fallthrough.
        if featureFlags.isEnabled(.useRustCoreForAppleApps) {
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

        guard let provider else {
            try await validateCredentials()
            return try await fetchBetaBuildLocalizations(buildId: buildId)
        }

        let endpoint = APIEndpoint.v1.betaBuildLocalizations.get(
            parameters: .init(filterBuild: [buildId], limit: 50)
        )
        let response = try await provider.request(endpoint)

        return response.data.map { item in
            BetaBuildLocalizationModel(
                id: item.id,
                locale: item.attributes?.locale ?? "",
                whatsNew: item.attributes?.whatsNew
            )
        }
    }

    func createBetaBuildLocalization(buildId: String, locale: String, whatsNew: String) async throws {
        // Strangler-fig migration: route this write through the shared Rust core
        // when the flag is ON; the Swift-SDK body below is the flag-OFF fallthrough.
        if featureFlags.isEnabled(.useRustCoreForAppleApps) {
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

        guard let provider else {
            try await validateCredentials()
            return try await createBetaBuildLocalization(buildId: buildId, locale: locale, whatsNew: whatsNew)
        }

        let body = BetaBuildLocalizationCreateRequest(
            data: .init(
                type: .betaBuildLocalizations,
                attributes: .init(whatsNew: whatsNew, locale: locale),
                relationships: .init(build: .init(data: .init(type: .builds, id: buildId)))
            )
        )
        let endpoint = APIEndpoint.v1.betaBuildLocalizations.post(body)
        _ = try await provider.request(endpoint)
        Log.print.info("[TestFlight] Created beta localization (\(locale)) for build \(buildId)")
    }

    func updateBetaBuildLocalization(id: String, whatsNew: String) async throws {
        // Strangler-fig migration: route this write through the shared Rust core
        // when the flag is ON; the Swift-SDK body below is the flag-OFF fallthrough.
        if featureFlags.isEnabled(.useRustCoreForAppleApps) {
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

        guard let provider else {
            try await validateCredentials()
            return try await updateBetaBuildLocalization(id: id, whatsNew: whatsNew)
        }

        let body = BetaBuildLocalizationUpdateRequest(
            data: .init(
                type: .betaBuildLocalizations,
                id: id,
                attributes: .init(whatsNew: whatsNew)
            )
        )
        let endpoint = APIEndpoint.v1.betaBuildLocalizations.id(id).patch(body)
        _ = try await provider.request(endpoint)
        Log.print.info("[TestFlight] Updated beta localization \(id)")
    }

    // MARK: - TestFlight: Builds for Group (continued)

    func removeBuildFromGroup(buildId: String, groupId: String) async throws {
        // Strangler-fig migration: route this write through the shared Rust core
        // when the flag is ON; the Swift-SDK body below is the flag-OFF fallthrough.
        if featureFlags.isEnabled(.useRustCoreForAppleApps) {
            let provider = try rustCoreProvider()
            guard let builds = provider.builds() else {
                throw translate(.Unsupported(message: "Builds capability is not available for this provider."))
            }
            try await callRustCore { try await builds.removeBuildFromGroup(buildId: buildId, groupId: groupId) }
            Log.print.info("[TestFlight] Removed build \(buildId) from group \(groupId) (Rust core)")
            return
        }

        guard let provider else {
            try await validateCredentials()
            return try await removeBuildFromGroup(buildId: buildId, groupId: groupId)
        }

        let body = BetaGroupBuildsLinkagesRequest(
            data: [.init(type: .builds, id: buildId)]
        )

        let endpoint = APIEndpoint.v1.betaGroups.id(groupId).relationships.builds.delete(body)
        _ = try await provider.request(endpoint)
        Log.print.info("[TestFlight] Removed build \(buildId) from group \(groupId)")
    }

    func addBuildToGroups(buildId: String, groupIds: [String]) async throws {
        // Strangler-fig migration: route this write through the shared Rust core
        // when the flag is ON; the Swift-SDK body below is the flag-OFF fallthrough.
        if featureFlags.isEnabled(.useRustCoreForAppleApps) {
            let provider = try rustCoreProvider()
            guard let builds = provider.builds() else {
                throw translate(.Unsupported(message: "Builds capability is not available for this provider."))
            }
            try await callRustCore { try await builds.addBuildToGroups(buildId: buildId, groupIds: groupIds) }
            Log.print.info("[TestFlight] Added build \(buildId) to \(groupIds.count) groups (Rust core)")
            return
        }

        guard let provider else {
            try await validateCredentials()
            return try await addBuildToGroups(buildId: buildId, groupIds: groupIds)
        }

        let body = BuildBetaGroupsLinkagesRequest(
            data: groupIds.map { .init(type: .betaGroups, id: $0) }
        )

        let endpoint = APIEndpoint.v1.builds.id(buildId).relationships.betaGroups.post(body)
        _ = try await provider.request(endpoint)
        Log.print.info("[TestFlight] Added build \(buildId) to \(groupIds.count) groups")
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
        if featureFlags.isEnabled(.useRustCoreForAppleApps) {
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

        guard let provider else {
            try await validateCredentials()
            return try await fetchCustomerReviewsPage(appId: appId, sort: sort, filterRating: filterRating, limit: limit, pageAfterResponse: pageAfterResponse)
        }

        typealias Params = APIEndpoint.V1.Apps.WithID.CustomerReviews.GetParameters

        let sortValue: [Params.Sort] = sort == "-createdDate" ? [.minuscreatedDate]
            : sort == "createdDate" ? [.createdDate]
            : sort == "-rating" ? [.minusrating]
            : sort == "rating" ? [.rating]
            : [.minuscreatedDate]

        let endpoint = APIEndpoint.v1.apps.id(appId).customerReviews.get(
            parameters: .init(
                filterRating: filterRating,
                sort: sortValue,
                limit: limit,
                include: [.response]
            )
        )

        let response: CustomerReviewsResponse
        if let previousResponse = pageAfterResponse as? CustomerReviewsResponse {
            guard let nextPage = try await provider.request(endpoint, pageAfter: previousResponse) else {
                return CustomerReviewsPage(reviews: [], hasNextPage: false, rawResponse: nil)
            }
            response = nextPage
        } else {
            response = try await provider.request(endpoint)
        }

        let hasNext = response.links.next != nil

        let responsesById: [String: CustomerReviewResponseV1] = {
            var dict: [String: CustomerReviewResponseV1] = [:]
            for item in response.included ?? [] {
                dict[item.id] = item
            }
            return dict
        }()

        let reviews = response.data.map { review in
            let responseRelId = review.relationships?.response?.data?.id
            let reviewResponse = responseRelId.flatMap { responsesById[$0] }

            return CustomerReviewModel(
                id: review.id,
                rating: review.attributes?.rating ?? 0,
                title: review.attributes?.title,
                body: review.attributes?.body,
                reviewerNickname: review.attributes?.reviewerNickname,
                createdDate: review.attributes?.createdDate,
                territory: review.attributes?.territory?.rawValue,
                responseId: reviewResponse?.id,
                responseBody: reviewResponse?.attributes?.responseBody,
                responseState: reviewResponse?.attributes?.state?.rawValue,
                responseDate: reviewResponse?.attributes?.lastModifiedDate
            )
        }

        return CustomerReviewsPage(reviews: reviews, hasNextPage: hasNext, rawResponse: response)
    }

    func replyToReview(reviewId: String, responseBody: String) async throws {
        if featureFlags.isEnabled(.useRustCoreForAppleApps) {
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

        guard let provider else {
            try await validateCredentials()
            return try await replyToReview(reviewId: reviewId, responseBody: responseBody)
        }

        let body = CustomerReviewResponseV1CreateRequest(
            data: .init(
                type: .customerReviewResponses,
                attributes: .init(responseBody: responseBody),
                relationships: .init(
                    review: .init(data: .init(type: .customerReviews, id: reviewId))
                )
            )
        )

        let endpoint = APIEndpoint.v1.customerReviewResponses.post(body)
        _ = try await provider.request(endpoint)
        Log.print.info("[Apple] Replied to review \(reviewId)")
    }

    func deleteReviewResponse(responseId: String) async throws {
        if featureFlags.isEnabled(.useRustCoreForAppleApps) {
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

        guard let provider else {
            try await validateCredentials()
            return try await deleteReviewResponse(responseId: responseId)
        }

        let endpoint = APIEndpoint.v1.customerReviewResponses.id(responseId).delete
        _ = try await provider.request(endpoint)
        Log.print.info("[Apple] Deleted review response \(responseId)")
    }

    // MARK: - Accessibility Declarations

    func fetchAccessibilityDeclarations(appId: String) async throws -> [AccessibilityDeclarationModel] {
        guard let provider else {
            try await validateCredentials()
            return try await fetchAccessibilityDeclarations(appId: appId)
        }

        let endpoint = APIEndpoint.v1.apps.id(appId).accessibilityDeclarations.get(
            parameters: .init(limit: 20)
        )

        let response = try await provider.request(endpoint)

        return response.data.map { decl in
            AccessibilityDeclarationModel(
                id: decl.id,
                deviceFamily: decl.attributes?.deviceFamily?.rawValue ?? "",
                state: decl.attributes?.state?.rawValue,
                supportsAudioDescriptions: decl.attributes?.isSupportsAudioDescriptions ?? false,
                supportsCaptions: decl.attributes?.isSupportsCaptions ?? false,
                supportsDarkInterface: decl.attributes?.isSupportsDarkInterface ?? false,
                supportsDifferentiateWithoutColor: decl.attributes?.isSupportsDifferentiateWithoutColorAlone ?? false,
                supportsLargerText: decl.attributes?.isSupportsLargerText ?? false,
                supportsReducedMotion: decl.attributes?.isSupportsReducedMotion ?? false,
                supportsSufficientContrast: decl.attributes?.isSupportsSufficientContrast ?? false,
                supportsVoiceControl: decl.attributes?.isSupportsVoiceControl ?? false,
                supportsVoiceover: decl.attributes?.isSupportsVoiceover ?? false
            )
        }
    }

    func updateAccessibilityDeclaration(_ model: AccessibilityDeclarationModel, publish: Bool = false) async throws {
        guard let provider else {
            try await validateCredentials()
            return try await updateAccessibilityDeclaration(model, publish: publish)
        }

        let body = AccessibilityDeclarationUpdateRequest(
            data: .init(
                type: .accessibilityDeclarations,
                id: model.id,
                attributes: .init(
                    isPublish: publish ? true : nil,
                    isSupportsAudioDescriptions: model.supportsAudioDescriptions,
                    isSupportsCaptions: model.supportsCaptions,
                    isSupportsDarkInterface: model.supportsDarkInterface,
                    isSupportsDifferentiateWithoutColorAlone: model.supportsDifferentiateWithoutColor,
                    isSupportsLargerText: model.supportsLargerText,
                    isSupportsReducedMotion: model.supportsReducedMotion,
                    isSupportsSufficientContrast: model.supportsSufficientContrast,
                    isSupportsVoiceControl: model.supportsVoiceControl,
                    isSupportsVoiceover: model.supportsVoiceover
                )
            )
        )

        let endpoint = APIEndpoint.v1.accessibilityDeclarations.id(model.id).patch(body)
        _ = try await provider.request(endpoint)
        Log.print.info("[Apple] Updated accessibility declaration \(model.id)")
    }

    func createAccessibilityDeclaration(appId: String, deviceFamily: String) async throws -> AccessibilityDeclarationModel {
        guard let provider else {
            try await validateCredentials()
            return try await createAccessibilityDeclaration(appId: appId, deviceFamily: deviceFamily)
        }

        guard let family = DeviceFamily(rawValue: deviceFamily) else {
            throw NSError(domain: "Accessibility", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid device family"])
        }

        let body = AccessibilityDeclarationCreateRequest(
            data: .init(
                type: .accessibilityDeclarations,
                attributes: .init(deviceFamily: family),
                relationships: .init(
                    app: .init(data: .init(type: .apps, id: appId))
                )
            )
        )

        let endpoint = APIEndpoint.v1.accessibilityDeclarations.post(body)
        let response = try await provider.request(endpoint)
        let decl = response.data

        Log.print.info("[Apple] Created accessibility declaration for \(deviceFamily)")
        return AccessibilityDeclarationModel(
            id: decl.id,
            deviceFamily: decl.attributes?.deviceFamily?.rawValue ?? deviceFamily,
            state: decl.attributes?.state?.rawValue,
            supportsAudioDescriptions: decl.attributes?.isSupportsAudioDescriptions ?? false,
            supportsCaptions: decl.attributes?.isSupportsCaptions ?? false,
            supportsDarkInterface: decl.attributes?.isSupportsDarkInterface ?? false,
            supportsDifferentiateWithoutColor: decl.attributes?.isSupportsDifferentiateWithoutColorAlone ?? false,
            supportsLargerText: decl.attributes?.isSupportsLargerText ?? false,
            supportsReducedMotion: decl.attributes?.isSupportsReducedMotion ?? false,
            supportsSufficientContrast: decl.attributes?.isSupportsSufficientContrast ?? false,
            supportsVoiceControl: decl.attributes?.isSupportsVoiceControl ?? false,
            supportsVoiceover: decl.attributes?.isSupportsVoiceover ?? false
        )
    }

    func deleteAccessibilityDeclaration(id: String) async throws {
        guard let provider else {
            try await validateCredentials()
            return try await deleteAccessibilityDeclaration(id: id)
        }

        let endpoint = APIEndpoint.v1.accessibilityDeclarations.id(id).delete
        _ = try await provider.request(endpoint)
        Log.print.info("[Apple] Deleted accessibility declaration \(id)")
    }

    // MARK: - App Review Detail

    func fetchAppReviewDetail(versionId: String) async throws -> AppReviewDetailModel? {
        guard let provider else {
            try await validateCredentials()
            return try await fetchAppReviewDetail(versionId: versionId)
        }

        do {
            let endpoint = APIEndpoint
                .v1
                .appStoreVersions
                .id(versionId)
                .appStoreReviewDetail
                .get()

            let result = try await provider.request(endpoint).data
            return AppReviewDetailModel(
                id: result.id,
                contactFirstName: result.attributes?.contactFirstName,
                contactLastName: result.attributes?.contactLastName,
                contactEmail: result.attributes?.contactEmail,
                contactPhone: result.attributes?.contactPhone,
                notes: result.attributes?.notes,
                demoAccountName: result.attributes?.demoAccountName,
                demoAccountPassword: result.attributes?.demoAccountPassword,
                isDemoAccountRequired: result.attributes?.isDemoAccountRequired
            )
        } catch {
            Log.print.info("[Apple] No review detail for version \(versionId)")
            return nil
        }
    }

    func updateAppReviewDetail(model: AppReviewDetailModel) async throws {
        guard let provider else {
            try await validateCredentials()
            return try await updateAppReviewDetail(model: model)
        }

        let body = AppStoreReviewDetailUpdateRequest(
            data: .init(
                type: .appStoreReviewDetails,
                id: model.id,
                attributes: .init(
                    contactFirstName: model.contactFirstName,
                    contactLastName: model.contactLastName,
                    contactPhone: model.contactPhone,
                    contactEmail: model.contactEmail,
                    demoAccountName: model.demoAccountName,
                    demoAccountPassword: model.demoAccountPassword,
                    isDemoAccountRequired: model.isDemoAccountRequired,
                    notes: model.notes
                )
            )
        )

        let endpoint = APIEndpoint.v1.appStoreReviewDetails.id(model.id).patch(body)
        _ = try await provider.request(endpoint)
        Log.print.info("[Apple] Updated review detail \(model.id)")
    }

    // MARK: - Beta App Review Detail (TestFlight Test Information)

    func fetchBetaAppReviewDetail(appId: String) async throws -> BetaAppReviewDetailModel? {
        // Strangler-fig migration: route this read through the shared Rust core
        // when the flag is ON; the Swift-SDK body below is the flag-OFF fallthrough.
        if featureFlags.isEnabled(.useRustCoreForAppleApps) {
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

        guard let provider else {
            try await validateCredentials()
            return try await fetchBetaAppReviewDetail(appId: appId)
        }

        do {
            let endpoint = APIEndpoint
                .v1
                .apps
                .id(appId)
                .betaAppReviewDetail
                .get()

            let result = try await provider.request(endpoint).data
            return BetaAppReviewDetailModel(
                id: result.id,
                contactFirstName: result.attributes?.contactFirstName,
                contactLastName: result.attributes?.contactLastName,
                contactEmail: result.attributes?.contactEmail,
                contactPhone: result.attributes?.contactPhone,
                demoAccountName: result.attributes?.demoAccountName,
                demoAccountPassword: result.attributes?.demoAccountPassword,
                isDemoAccountRequired: result.attributes?.isDemoAccountRequired,
                notes: result.attributes?.notes
            )
        } catch {
            Log.print.info("[Apple] No beta review detail for app \(appId)")
            return nil
        }
    }

    func updateBetaAppReviewDetail(model: BetaAppReviewDetailModel) async throws {
        // Strangler-fig migration: route this write through the shared Rust core
        // when the flag is ON; the Swift-SDK body below is the flag-OFF fallthrough.
        if featureFlags.isEnabled(.useRustCoreForAppleApps) {
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

        guard let provider else {
            try await validateCredentials()
            return try await updateBetaAppReviewDetail(model: model)
        }

        let body = BetaAppReviewDetailUpdateRequest(
            data: .init(
                type: .betaAppReviewDetails,
                id: model.id,
                attributes: .init(
                    contactFirstName: model.contactFirstName,
                    contactLastName: model.contactLastName,
                    contactPhone: model.contactPhone,
                    contactEmail: model.contactEmail,
                    demoAccountName: model.demoAccountName,
                    demoAccountPassword: model.demoAccountPassword,
                    isDemoAccountRequired: model.isDemoAccountRequired,
                    notes: model.notes
                )
            )
        )

        let endpoint = APIEndpoint.v1.betaAppReviewDetails.id(model.id).patch(body)
        _ = try await provider.request(endpoint)
        Log.print.info("[Apple] Updated beta review detail \(model.id)")
    }

    // MARK: - Beta App Localizations (TestFlight description / feedback email)

    func fetchBetaAppLocalizations(appId: String) async throws -> [BetaAppLocalizationModel] {
        // Strangler-fig migration: route this read through the shared Rust core
        // when the flag is ON; the Swift-SDK body below is the flag-OFF fallthrough.
        if featureFlags.isEnabled(.useRustCoreForAppleApps) {
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

        guard let provider else {
            try await validateCredentials()
            return try await fetchBetaAppLocalizations(appId: appId)
        }

        let endpoint = APIEndpoint
            .v1
            .apps
            .id(appId)
            .betaAppLocalizations
            .get()

        let response = try await provider.request(endpoint)
        return response.data.map { entry in
            BetaAppLocalizationModel(
                id: entry.id,
                locale: entry.attributes?.locale ?? "",
                feedbackEmail: entry.attributes?.feedbackEmail,
                description: entry.attributes?.description
            )
        }
    }

    func updateBetaAppLocalization(id: String, feedbackEmail: String?, description: String?) async throws {
        // Strangler-fig migration: route this write through the shared Rust core
        // when the flag is ON; the Swift-SDK body below is the flag-OFF fallthrough.
        if featureFlags.isEnabled(.useRustCoreForAppleApps) {
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

        guard let provider else {
            try await validateCredentials()
            return try await updateBetaAppLocalization(id: id, feedbackEmail: feedbackEmail, description: description)
        }

        let body = BetaAppLocalizationUpdateRequest(
            data: .init(
                type: .betaAppLocalizations,
                id: id,
                attributes: .init(
                    feedbackEmail: feedbackEmail,
                    description: description
                )
            )
        )

        let endpoint = APIEndpoint.v1.betaAppLocalizations.id(id).patch(body)
        _ = try await provider.request(endpoint)
        Log.print.info("[Apple] Updated beta app localization \(id)")
    }

    func createBetaAppLocalization(
        appId: String,
        locale: String,
        feedbackEmail: String?,
        description: String?
    ) async throws -> BetaAppLocalizationModel {
        // Strangler-fig migration: route this write through the shared Rust core
        // when the flag is ON; the Swift-SDK body below is the flag-OFF fallthrough.
        if featureFlags.isEnabled(.useRustCoreForAppleApps) {
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

        guard let provider else {
            try await validateCredentials()
            return try await createBetaAppLocalization(
                appId: appId,
                locale: locale,
                feedbackEmail: feedbackEmail,
                description: description
            )
        }

        let body = BetaAppLocalizationCreateRequest(
            data: .init(
                type: .betaAppLocalizations,
                attributes: .init(
                    feedbackEmail: feedbackEmail,
                    description: description,
                    locale: locale
                ),
                relationships: .init(
                    app: .init(data: .init(type: .apps, id: appId))
                )
            )
        )

        let endpoint = APIEndpoint.v1.betaAppLocalizations.post(body)
        let response = try await provider.request(endpoint)
        Log.print.info("[Apple] Created beta app localization \(response.data.id)")
        return BetaAppLocalizationModel(
            id: response.data.id,
            locale: response.data.attributes?.locale ?? locale,
            feedbackEmail: response.data.attributes?.feedbackEmail,
            description: response.data.attributes?.description
        )
    }

    // MARK: - Screenshot Sets

    func fetchScreenshotSets(localizationId: String) async throws -> [ScreenshotSetModel] {
        guard let provider else {
            try await validateCredentials()
            return try await fetchScreenshotSets(localizationId: localizationId)
        }

        let endpoint = APIEndpoint
            .v1
            .appStoreVersionLocalizations
            .id(localizationId)
            .appScreenshotSets
            .get(parameters: .init(include: [.appScreenshots]))

        let response = try await provider.request(endpoint)

        return response.data.compactMap { set in
            let displayType = set.attributes?.screenshotDisplayType?.rawValue
            let screenshotIds = set.relationships?.appScreenshots?.data?.map(\.id) ?? []

            let screenshots: [ScreenshotModel] = (response.included ?? []).compactMap { included in
                guard case .appScreenshot(let screenshot) = included,
                      screenshotIds.contains(screenshot.id) else { return nil }
                return ScreenshotModel(
                    id: screenshot.id,
                    imageUrl: screenshot.attributes?.imageAsset?.toIconUrl(),
                    fileName: screenshot.attributes?.fileName,
                    fileSize: screenshot.attributes?.fileSize,
                    width: screenshot.attributes?.imageAsset?.width,
                    height: screenshot.attributes?.imageAsset?.height
                )
            }

            return ScreenshotSetModel(
                id: set.id,
                displayType: displayType,
                screenshots: screenshots
            )
        }
    }

    // MARK: - Phased Release

    func fetchPhasedRelease(versionId: String) async throws -> PhasedReleaseModel? {
        guard let provider else {
            try await validateCredentials()
            return try await fetchPhasedRelease(versionId: versionId)
        }

        do {
            let endpoint = APIEndpoint
                .v1
                .appStoreVersions
                .id(versionId)
                .appStoreVersionPhasedRelease
                .get()

            let result = try await provider.request(endpoint).data
            return PhasedReleaseModel(
                id: result.id,
                state: result.attributes?.phasedReleaseState.flatMap { PhasedReleaseStatus(rawValue: $0.rawValue) },
                startDate: result.attributes?.startDate,
                totalPauseDuration: result.attributes?.totalPauseDuration,
                currentDayNumber: result.attributes?.currentDayNumber
            )
        } catch {
            Log.print.info("[Apple] No phased release for version \(versionId)")
            return nil
        }
    }

    func createPhasedRelease(versionId: String, state: PhasedReleaseState) async throws -> PhasedReleaseModel {
        guard let provider else {
            try await validateCredentials()
            return try await createPhasedRelease(versionId: versionId, state: state)
        }

        let body = AppStoreVersionPhasedReleaseCreateRequest(
            data: .init(
                type: .appStoreVersionPhasedReleases,
                attributes: .init(phasedReleaseState: state),
                relationships: .init(
                    appStoreVersion: .init(
                        data: .init(type: .appStoreVersions, id: versionId)
                    )
                )
            )
        )

        let endpoint = APIEndpoint.v1.appStoreVersionPhasedReleases.post(body)
        let result = try await provider.request(endpoint).data
        Log.print.info("[Apple] Created phased release for version \(versionId)")
        return PhasedReleaseModel(
            id: result.id,
            state: result.attributes?.phasedReleaseState.flatMap { PhasedReleaseStatus(rawValue: $0.rawValue) },
            startDate: result.attributes?.startDate,
            totalPauseDuration: result.attributes?.totalPauseDuration,
            currentDayNumber: result.attributes?.currentDayNumber
        )
    }

    func deletePhasedRelease(id: String) async throws {
        guard let provider else {
            try await validateCredentials()
            return try await deletePhasedRelease(id: id)
        }

        let endpoint = APIEndpoint.v1.appStoreVersionPhasedReleases.id(id).delete
        _ = try await provider.request(endpoint)
        Log.print.info("[Apple] Deleted phased release \(id)")
    }

    @discardableResult
    func updatePhasedReleaseState(id: String, state: PhasedReleaseState) async throws -> PhasedReleaseModel {
        guard let provider else {
            try await validateCredentials()
            return try await updatePhasedReleaseState(id: id, state: state)
        }

        let body = AppStoreVersionPhasedReleaseUpdateRequest(
            data: .init(
                type: .appStoreVersionPhasedReleases,
                id: id,
                attributes: .init(phasedReleaseState: state)
            )
        )

        let endpoint = APIEndpoint.v1.appStoreVersionPhasedReleases.id(id).patch(body)
        let result = try await provider.request(endpoint).data
        Log.print.info("[Apple] Updated phased release \(id) to state \(state.rawValue)")
        return PhasedReleaseModel(
            id: result.id,
            state: result.attributes?.phasedReleaseState.flatMap { PhasedReleaseStatus(rawValue: $0.rawValue) },
            startDate: result.attributes?.startDate,
            totalPauseDuration: result.attributes?.totalPauseDuration,
            currentDayNumber: result.attributes?.currentDayNumber
        )
    }

    // MARK: - App Info

    func fetchAppInfo(appId: String) async throws -> (AppInfoModel, AgeRatingDeclarationModel?) {
        guard let provider else {
            try await validateCredentials()
            return try await fetchAppInfo(appId: appId)
        }

        let request = APIEndpoint.v1.apps.id(appId).appInfos.get(
            parameters: .init(
                fieldsAppInfos: [.appStoreAgeRating, .primaryCategory, .primarySubcategoryOne, .secondaryCategory, .secondarySubcategoryOne],
                fieldsAgeRatingDeclarations: [
                    .alcoholTobaccoOrDrugUseOrReferences, .contests, .gamblingSimulated,
                    .gunsOrOtherWeapons, .medicalOrTreatmentInformation, .profanityOrCrudeHumor,
                    .sexualContentGraphicAndNudity, .sexualContentOrNudity, .horrorOrFearThemes,
                    .matureOrSuggestiveThemes, .violenceCartoonOrFantasy, .violenceRealistic,
                    .violenceRealisticProlongedGraphicOrSadistic, .advertising, .gambling,
                    .unrestrictedWebAccess, .userGeneratedContent, .ageRatingOverrideV2
                ],
                fieldsAppInfoLocalizations: [.locale, .name, .subtitle, .privacyPolicyURL, .privacyChoicesURL, .privacyPolicyText],
                fieldsAppCategories: [.platforms],
                limit: 1,
                include: [.ageRatingDeclaration, .appInfoLocalizations, .primaryCategory, .primarySubcategoryOne, .secondaryCategory, .secondarySubcategoryOne],
                limitAppInfoLocalizations: 50
            )
        )

        let response = try await provider.request(request)
        guard let info = response.data.first else {
            throw NSError(domain: "AppInfo", code: 404, userInfo: [NSLocalizedDescriptionKey: "App info not found"])
        }

        // Fetch app-level fields (sku, primaryLocale, contentRights)
        let appRequest = APIEndpoint.v1.apps.id(appId).get(
            parameters: .init(fieldsApps: [.sku, .primaryLocale, .contentRightsDeclaration])
        )
        let appResponse = try await provider.request(appRequest)
        let appAttrs = appResponse.data.attributes

        let included = response.included ?? []

        // Map localizations from included
        var localizations: [AppInfoLocalizationModel] = []
        for item in included {
            if case .appInfoLocalization(let loc) = item {
                let model = AppInfoLocalizationModel(
                    id: loc.id,
                    locale: loc.attributes?.locale ?? "",
                    name: loc.attributes?.name,
                    subtitle: loc.attributes?.subtitle,
                    privacyPolicyUrl: loc.attributes?.privacyPolicyURL,
                    privacyChoicesUrl: loc.attributes?.privacyChoicesURL,
                    privacyPolicyText: loc.attributes?.privacyPolicyText
                )
                localizations.append(model)
            }
        }

        // Map category IDs from relationships (most reliable source)
        let primaryCatId = info.relationships?.primaryCategory?.data?.id
        let primarySubCatOneId = info.relationships?.primarySubcategoryOne?.data?.id
        let secondaryCatId = info.relationships?.secondaryCategory?.data?.id
        let secondarySubCatOneId = info.relationships?.secondarySubcategoryOne?.data?.id
        let primaryCategoryId = primaryCatId
        let primaryCategoryName = primaryCatId.map { AppleAccountConnection.formatCategoryId($0) }
        let primarySubcategoryOneId = primarySubCatOneId
        let primarySubcategoryOneName = primarySubCatOneId.map { id in
            AppleAccountConnection.formatSubcategoryId(id, parentId: primaryCatId)
        }
        let secondaryCategoryId = secondaryCatId
        let secondaryCategoryName = secondaryCatId.map { AppleAccountConnection.formatCategoryId($0) }
        let secondarySubcategoryOneId = secondarySubCatOneId

        // Map age rating declaration from included
        var ageRating: AgeRatingDeclarationModel?
        for item in included {
            if case .ageRatingDeclaration(let ar) = item {
                let attrs = ar.attributes
                ageRating = AgeRatingDeclarationModel(
                    id: ar.id,
                    alcoholTobaccoOrDrugUseOrReferences: attrs?.alcoholTobaccoOrDrugUseOrReferences?.rawValue,
                    contests: attrs?.contests?.rawValue,
                    gamblingSimulated: attrs?.gamblingSimulated?.rawValue,
                    gunsOrOtherWeapons: attrs?.gunsOrOtherWeapons?.rawValue,
                    medicalOrTreatmentInformation: attrs?.medicalOrTreatmentInformation?.rawValue,
                    profanityOrCrudeHumor: attrs?.profanityOrCrudeHumor?.rawValue,
                    sexualContentGraphicAndNudity: attrs?.sexualContentGraphicAndNudity?.rawValue,
                    sexualContentOrNudity: attrs?.sexualContentOrNudity?.rawValue,
                    horrorOrFearThemes: attrs?.horrorOrFearThemes?.rawValue,
                    matureOrSuggestiveThemes: attrs?.matureOrSuggestiveThemes?.rawValue,
                    violenceCartoonOrFantasy: attrs?.violenceCartoonOrFantasy?.rawValue,
                    violenceRealistic: attrs?.violenceRealistic?.rawValue,
                    violenceRealisticProlongedGraphicOrSadistic: attrs?.violenceRealisticProlongedGraphicOrSadistic?.rawValue,
                    isAdvertising: attrs?.isAdvertising,
                    isGambling: attrs?.isGambling,
                    isUnrestrictedWebAccess: attrs?.isUnrestrictedWebAccess,
                    isUserGeneratedContent: attrs?.isUserGeneratedContent,
                    ageRatingOverrideV2: attrs?.ageRatingOverrideV2?.rawValue
                )
            }
        }

        let appInfo = AppInfoModel(
            id: info.id,
            appId: appId,
            sku: appAttrs?.sku,
            primaryLocale: appAttrs?.primaryLocale,
            contentRightsDeclaration: appAttrs?.contentRightsDeclaration?.rawValue,
            primaryCategoryId: primaryCategoryId,
            primaryCategoryName: primaryCategoryName,
            primarySubcategoryOneId: primarySubcategoryOneId,
            primarySubcategoryOneName: primarySubcategoryOneName,
            secondaryCategoryId: secondaryCategoryId,
            secondaryCategoryName: secondaryCategoryName,
            secondarySubcategoryOneId: secondarySubcategoryOneId,
            ageRatingDeclarationId: ageRating?.id,
            appStoreAgeRating: info.attributes?.appStoreAgeRating?.rawValue,
            localizations: localizations
        )

        Log.print.info("[Apple] Fetched app info for \(appId)")
        return (appInfo, ageRating)
    }

    // MARK: - App Info Localizations

    func fetchAppInfoLocalizations(appInfoId: String) async throws -> [AppInfoLocalizationModel] {
        guard let provider else {
            try await validateCredentials()
            return try await fetchAppInfoLocalizations(appInfoId: appInfoId)
        }

        let endpoint = APIEndpoint.v1.appInfos.id(appInfoId).appInfoLocalizations.get()
        let response = try await provider.request(endpoint)

        return response.data.map { loc in
            AppInfoLocalizationModel(
                id: loc.id,
                locale: loc.attributes?.locale ?? "",
                name: loc.attributes?.name,
                subtitle: loc.attributes?.subtitle,
                privacyPolicyUrl: loc.attributes?.privacyPolicyURL,
                privacyChoicesUrl: loc.attributes?.privacyChoicesURL,
                privacyPolicyText: loc.attributes?.privacyPolicyText
            )
        }
    }

    func updateAppInfoLocalization(id: String, name: String, subtitle: String?) async throws {
        guard let provider else {
            try await validateCredentials()
            return try await updateAppInfoLocalization(id: id, name: name, subtitle: subtitle)
        }

        let body = AppInfoLocalizationUpdateRequest(
            data: .init(
                type: .appInfoLocalizations,
                id: id,
                attributes: .init(name: name, subtitle: subtitle)
            )
        )

        let endpoint = APIEndpoint.v1.appInfoLocalizations.id(id).patch(body)
        _ = try await provider.request(endpoint)
        Log.print.info("[Apple] Updated app info localization \(id)")
    }

    func updateAppInfoLocalizationPrivacy(
        id: String,
        privacyPolicyUrl: String?,
        privacyChoicesUrl: String?,
        privacyPolicyText: String?
    ) async throws {
        guard let provider else {
            try await validateCredentials()
            return try await updateAppInfoLocalizationPrivacy(
                id: id,
                privacyPolicyUrl: privacyPolicyUrl,
                privacyChoicesUrl: privacyChoicesUrl,
                privacyPolicyText: privacyPolicyText
            )
        }

        let body = AppInfoLocalizationUpdateRequest(
            data: .init(
                type: .appInfoLocalizations,
                id: id,
                attributes: .init(
                    privacyPolicyURL: privacyPolicyUrl,
                    privacyChoicesURL: privacyChoicesUrl,
                    privacyPolicyText: privacyPolicyText
                )
            )
        )

        let endpoint = APIEndpoint.v1.appInfoLocalizations.id(id).patch(body)
        _ = try await provider.request(endpoint)
        Log.print.info("[Apple] Updated privacy for localization \(id)")
    }

    func createAppInfoLocalization(
        appInfoId: String,
        locale: String,
        name: String,
        subtitle: String?
    ) async throws -> AppInfoLocalizationModel {
        guard let provider else {
            try await validateCredentials()
            return try await createAppInfoLocalization(appInfoId: appInfoId, locale: locale, name: name, subtitle: subtitle)
        }

        let body = AppInfoLocalizationCreateRequest(
            data: .init(
                type: .appInfoLocalizations,
                attributes: .init(locale: locale, name: name, subtitle: subtitle),
                relationships: .init(
                    appInfo: .init(data: .init(type: .appInfos, id: appInfoId))
                )
            )
        )

        let response = try await provider.request(APIEndpoint.v1.appInfoLocalizations.post(body))
        Log.print.info("[Apple] Created app info localization for \(locale)")
        return AppInfoLocalizationModel(
            id: response.data.id,
            locale: response.data.attributes?.locale ?? locale,
            name: response.data.attributes?.name ?? name,
            subtitle: response.data.attributes?.subtitle ?? subtitle
        )
    }

    func deleteAppInfoLocalization(id: String) async throws {
        guard let provider else {
            try await validateCredentials()
            return try await deleteAppInfoLocalization(id: id)
        }

        let endpoint = APIEndpoint.v1.appInfoLocalizations.id(id).delete
        _ = try await provider.request(endpoint)
        Log.print.info("[Apple] Deleted app info localization \(id)")
    }

    // MARK: - App Categories

    func fetchAppCategories() async throws -> [AppCategoryModel] {
        guard let provider else {
            try await validateCredentials()
            return try await fetchAppCategories()
        }

        let endpoint = APIEndpoint.v1.appCategories.get(
            parameters: .init(
                filterPlatforms: [.ios],
                isExistsParent: false,
                include: [.subcategories]
            )
        )
        let response = try await provider.request(endpoint)

        let subcategoryMap: [String: AppCategoryModel] = Dictionary(
            uniqueKeysWithValues: (response.included ?? []).map { sub in
                (sub.id, AppCategoryModel(id: sub.id))
            }
        )

        return response.data.map { cat in
            let subcategoryIds = cat.relationships?.subcategories?.data?.map(\.id) ?? []
            let subcategories = subcategoryIds.compactMap { subcategoryMap[$0] }
            return AppCategoryModel(id: cat.id, subcategories: subcategories)
        }
    }

    func updateAppInfoCategory(
        appInfoId: String,
        primaryCategoryId: String?,
        subcategoryOneId: String?,
        secondaryCategoryId: String?,
        secondarySubcategoryOneId: String?
    ) async throws {
        guard let provider else {
            try await validateCredentials()
            return try await updateAppInfoCategory(
                appInfoId: appInfoId,
                primaryCategoryId: primaryCategoryId,
                subcategoryOneId: subcategoryOneId,
                secondaryCategoryId: secondaryCategoryId,
                secondarySubcategoryOneId: secondarySubcategoryOneId
            )
        }

        typealias Rels = AppInfoUpdateRequest.Data.Relationships
        let primaryCat = primaryCategoryId.map { id in
            Rels.PrimaryCategory(data: .init(type: .appCategories, id: id))
        }
        let subCatOne = subcategoryOneId.map { id in
            Rels.PrimarySubcategoryOne(data: .init(type: .appCategories, id: id))
        }
        let secondaryCat = secondaryCategoryId.map { id in
            Rels.SecondaryCategory(data: .init(type: .appCategories, id: id))
        }
        let secondarySubCatOne = secondarySubcategoryOneId.map { id in
            Rels.SecondarySubcategoryOne(data: .init(type: .appCategories, id: id))
        }

        let body = AppInfoUpdateRequest(
            data: .init(
                type: .appInfos,
                id: appInfoId,
                relationships: .init(
                    primaryCategory: primaryCat,
                    primarySubcategoryOne: subCatOne,
                    secondaryCategory: secondaryCat,
                    secondarySubcategoryOne: secondarySubCatOne
                )
            )
        )

        let endpoint = APIEndpoint.v1.appInfos.id(appInfoId).patch(body)
        _ = try await provider.request(endpoint)
        Log.print.info("[Apple] Updated app info category for \(appInfoId)")
    }

    func updateApp(id: String, contentRightsDeclaration: String? = nil, primaryLocale: String? = nil) async throws {
        guard let provider else {
            try await validateCredentials()
            return try await updateApp(id: id, contentRightsDeclaration: contentRightsDeclaration, primaryLocale: primaryLocale)
        }

        let rights = contentRightsDeclaration.flatMap {
            AppUpdateRequest.Data.Attributes.ContentRightsDeclaration(rawValue: $0)
        }

        let body = AppUpdateRequest(
            data: .init(
                type: .apps,
                id: id,
                attributes: .init(
                    primaryLocale: primaryLocale,
                    contentRightsDeclaration: rights
                )
            )
        )

        let endpoint = APIEndpoint.v1.apps.id(id).patch(body)
        _ = try await provider.request(endpoint)
        Log.print.info("[Apple] Updated app \(id)")
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
        guard let provider else {
            try await validateCredentials()
            return try await updateAgeRating(
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

        typealias Attrs = AgeRatingDeclarationUpdateRequest.Data.Attributes

        let body = AgeRatingDeclarationUpdateRequest(
            data: .init(
                type: .ageRatingDeclarations,
                id: id,
                attributes: .init(
                    isAdvertising: isAdvertising,
                    alcoholTobaccoOrDrugUseOrReferences: Attrs.AlcoholTobaccoOrDrugUseOrReferences(rawValue: alcoholTobacco),
                    contests: Attrs.Contests(rawValue: contests),
                    isGambling: isGambling,
                    gamblingSimulated: Attrs.GamblingSimulated(rawValue: gamblingSimulated),
                    gunsOrOtherWeapons: Attrs.GunsOrOtherWeapons(rawValue: gunsOrOtherWeapons),
                    medicalOrTreatmentInformation: Attrs.MedicalOrTreatmentInformation(rawValue: medicalInformation),
                    profanityOrCrudeHumor: Attrs.ProfanityOrCrudeHumor(rawValue: profanity),
                    sexualContentGraphicAndNudity: Attrs.SexualContentGraphicAndNudity(rawValue: sexualContentGraphic),
                    sexualContentOrNudity: Attrs.SexualContentOrNudity(rawValue: sexualContentOrNudity),
                    horrorOrFearThemes: Attrs.HorrorOrFearThemes(rawValue: horrorOrFear),
                    matureOrSuggestiveThemes: Attrs.MatureOrSuggestiveThemes(rawValue: matureOrSuggestive),
                    isUnrestrictedWebAccess: isUnrestrictedWebAccess,
                    isUserGeneratedContent: isUserGeneratedContent,
                    violenceCartoonOrFantasy: Attrs.ViolenceCartoonOrFantasy(rawValue: violenceCartoon),
                    violenceRealisticProlongedGraphicOrSadistic: Attrs.ViolenceRealisticProlongedGraphicOrSadistic(rawValue: violenceGraphic),
                    violenceRealistic: Attrs.ViolenceRealistic(rawValue: violenceRealistic),
                    ageRatingOverrideV2: Attrs.AgeRatingOverrideV2(rawValue: ageRatingOverride)
                )
            )
        )

        let endpoint = APIEndpoint.v1.ageRatingDeclarations.id(id).patch(body)
        _ = try await provider.request(endpoint)
        Log.print.info("[Apple] Updated age rating \(id)")
    }

    // MARK: - Review Submissions

    func submitForReview(appId: String, versionId: String, platform: AppPlatform?) async throws {
        guard let provider else {
            try await validateCredentials()
            return try await submitForReview(appId: appId, versionId: versionId, platform: platform)
        }

        // 1. Create review submission
        let sdkPlatform: Platform? = platform.flatMap { Platform(rawValue: $0.rawValue) }
        let createBody = ReviewSubmissionCreateRequest(
            data: .init(
                type: .reviewSubmissions,
                attributes: sdkPlatform.map { .init(platform: $0) },
                relationships: .init(
                    app: .init(data: .init(type: .apps, id: appId))
                )
            )
        )
        let submission = try await provider.request(
            APIEndpoint.v1.reviewSubmissions.post(createBody)
        )
        let submissionId = submission.data.id

        // 2. Add version as item
        let itemBody = ReviewSubmissionItemCreateRequest(
            data: .init(
                type: .reviewSubmissionItems,
                relationships: .init(
                    reviewSubmission: .init(data: .init(type: .reviewSubmissions, id: submissionId)),
                    appStoreVersion: .init(data: .init(type: .appStoreVersions, id: versionId))
                )
            )
        )
        _ = try await provider.request(
            APIEndpoint.v1.reviewSubmissionItems.post(itemBody)
        )

        // 3. Submit
        let submitBody = ReviewSubmissionUpdateRequest(
            data: .init(
                type: .reviewSubmissions,
                id: submissionId,
                attributes: .init(isSubmitted: true)
            )
        )
        _ = try await provider.request(
            APIEndpoint.v1.reviewSubmissions.id(submissionId).patch(submitBody)
        )

        Log.print.info("[Apple] Submitted version \(versionId) for review")
    }

    func cancelReview(appId: String) async throws {
        guard let provider else {
            try await validateCredentials()
            return try await cancelReview(appId: appId)
        }

        // Find active submission
        let request = APIEndpoint.v1.reviewSubmissions.get(
            parameters: .init(
                filterState: [.waitingForReview, .inReview],
                filterApp: [appId]
            )
        )
        let response = try await provider.request(request)

        guard let submission = response.data.first else {
            Log.print.info("[Apple] No active review submission found for app \(appId)")
            return
        }

        // Cancel it
        let cancelBody = ReviewSubmissionUpdateRequest(
            data: .init(
                type: .reviewSubmissions,
                id: submission.id,
                attributes: .init(isCanceled: true)
            )
        )
        _ = try await provider.request(
            APIEndpoint.v1.reviewSubmissions.id(submission.id).patch(cancelBody)
        )

        Log.print.info("[Apple] Cancelled review for app \(appId)")
    }

    func releaseVersion(versionId: String) async throws {
        guard let provider else {
            try await validateCredentials()
            return try await releaseVersion(versionId: versionId)
        }

        let body = AppStoreVersionReleaseRequestCreateRequest(
            data: .init(
                type: .appStoreVersionReleaseRequests,
                relationships: .init(
                    appStoreVersion: .init(
                        data: .init(
                            type: .appStoreVersions,
                            id: versionId
                        )
                    )
                )
            )
        )

        let endpoint = APIEndpoint.v1.appStoreVersionReleaseRequests.post(body)
        _ = try await provider.request(endpoint)
        Log.print.info("[Apple] Released version \(versionId)")
    }

    func rejectVersion(appId: String) async throws {
        guard let provider else {
            try await validateCredentials()
            return try await rejectVersion(appId: appId)
        }

        // Find any completing/complete submission to reject
        let request = APIEndpoint.v1.reviewSubmissions.get(
            parameters: .init(
                filterApp: [appId]
            )
        )
        let response = try await provider.request(request)

        guard let submission = response.data.first else {
            Log.print.info("[Apple] No review submission found for app \(appId)")
            return
        }

        let cancelBody = ReviewSubmissionUpdateRequest(
            data: .init(
                type: .reviewSubmissions,
                id: submission.id,
                attributes: .init(isCanceled: true)
            )
        )
        _ = try await provider.request(
            APIEndpoint.v1.reviewSubmissions.id(submission.id).patch(cancelBody)
        )

        Log.print.info("[Apple] Rejected version for app \(appId)")
    }

    func disconnect() {
        provider = nil
        Log.print.info("[Apple] Disconnected")
    }

    // MARK: - Certificates

    func fetchCertificates() async throws -> [CertificateModel] {
        guard let provider else {
            try await validateCredentials()
            return try await fetchCertificates()
        }

        let endpoint = APIEndpoint
            .v1
            .certificates
            .get(parameters: .init(sort: [.displayName], limit: 200))

        let response = try await provider.request(endpoint)

        let models = response.data.map { cert in
            CertificateModel(
                id: cert.id,
                displayName: cert.attributes?.displayName ?? cert.attributes?.name ?? "",
                name: cert.attributes?.name ?? "",
                certificateType: cert.attributes?.certificateType?.rawValue ?? "",
                platform: cert.attributes?.platform?.rawValue,
                serialNumber: cert.attributes?.serialNumber,
                expirationDate: cert.attributes?.expirationDate,
                isActivated: cert.attributes?.isActivated ?? false
            )
        }

        Log.print.info("[Apple] Fetched \(models.count) certificates")
        return models
    }

    func fetchCertificateContent(id: String) async throws -> String? {
        guard let provider else {
            try await validateCredentials()
            return try await fetchCertificateContent(id: id)
        }

        let endpoint = APIEndpoint
            .v1
            .certificates
            .id(id)
            .get(parameters: .init(
                fieldsCertificates: [
                    .certificateContent,
                    .displayName,
                    .name,
                    .certificateType,
                    .platform,
                    .serialNumber,
                    .expirationDate,
                    .activated
                ]
            ))

        let response = try await provider.request(endpoint)
        return response.data.attributes?.certificateContent
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
        guard let provider else {
            try await validateCredentials()
            return try await createCertificate(
                csrContent: csrContent,
                certificateTypeRaw: certificateTypeRaw,
                passTypeId: passTypeId,
                merchantId: merchantId
            )
        }

        guard let typeEnum = CertificateType(rawValue: certificateTypeRaw) else {
            throw NSError(
                domain: "Certificates",
                code: 400,
                userInfo: [NSLocalizedDescriptionKey: "Unsupported certificate type: \(certificateTypeRaw)"]
            )
        }

        var relationships: CertificateCreateRequest.Data.Relationships?
        if let passTypeId, !passTypeId.isEmpty {
            relationships = .init(
                passTypeID: .init(data: .init(type: .passTypeIDs, id: passTypeId))
            )
        } else if let merchantId, !merchantId.isEmpty {
            relationships = .init(
                merchantID: .init(data: .init(type: .merchantIDs, id: merchantId))
            )
        }

        let body = CertificateCreateRequest(
            data: .init(
                type: .certificates,
                attributes: .init(csrContent: csrContent, certificateType: typeEnum),
                relationships: relationships
            )
        )

        let endpoint = APIEndpoint.v1.certificates.post(body)
        let response = try await provider.request(endpoint)
        let cert = response.data

        let model = CertificateModel(
            id: cert.id,
            displayName: cert.attributes?.displayName ?? cert.attributes?.name ?? "",
            name: cert.attributes?.name ?? "",
            certificateType: cert.attributes?.certificateType?.rawValue ?? certificateTypeRaw,
            platform: cert.attributes?.platform?.rawValue,
            serialNumber: cert.attributes?.serialNumber,
            expirationDate: cert.attributes?.expirationDate,
            isActivated: cert.attributes?.isActivated ?? false
        )

        Log.print.info("[Apple] Created certificate \(model.id) (\(certificateTypeRaw))")
        return CreatedCertificate(certificate: model, content: cert.attributes?.certificateContent)
    }

    func revokeCertificate(id: String) async throws {
        guard let provider else {
            try await validateCredentials()
            return try await revokeCertificate(id: id)
        }

        let endpoint = APIEndpoint.v1.certificates.id(id).delete
        _ = try await provider.request(endpoint)
        Log.print.info("[Apple] Revoked certificate \(id)")
    }

    // MARK: - Bundle Identifiers

    func fetchBundleIds() async throws -> [BundleIdentifierModel] {
        guard let provider else {
            try await validateCredentials()
            return try await fetchBundleIds()
        }

        let endpoint = APIEndpoint
            .v1
            .bundleIDs
            .get(parameters: .init(sort: [.name], limit: 200))

        let response = try await provider.request(endpoint)

        let models = response.data.map { bundle in
            BundleIdentifierModel(
                id: bundle.id,
                identifier: bundle.attributes?.identifier ?? "",
                name: bundle.attributes?.name ?? "",
                platform: bundle.attributes?.platform?.rawValue ?? "",
                seedId: bundle.attributes?.seedID
            )
        }
        Log.print.info("[Apple] Fetched \(models.count) bundle identifiers")
        return models
    }

    func createBundleId(
        identifier: String,
        name: String,
        platformRaw: String
    ) async throws -> BundleIdentifierModel {
        guard let provider else {
            try await validateCredentials()
            return try await createBundleId(identifier: identifier, name: name, platformRaw: platformRaw)
        }

        guard let platform = BundleIDPlatform(rawValue: platformRaw) else {
            throw NSError(domain: "BundleId", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid platform: \(platformRaw)"])
        }

        let body = BundleIDCreateRequest(
            data: .init(
                type: .bundleIDs,
                attributes: .init(name: name, platform: platform, identifier: identifier)
            )
        )

        let endpoint = APIEndpoint.v1.bundleIDs.post(body)
        let response = try await provider.request(endpoint)
        let bundle = response.data

        Log.print.info("[Apple] Created bundle identifier \(identifier)")
        return BundleIdentifierModel(
            id: bundle.id,
            identifier: bundle.attributes?.identifier ?? identifier,
            name: bundle.attributes?.name ?? name,
            platform: bundle.attributes?.platform?.rawValue ?? platformRaw,
            seedId: bundle.attributes?.seedID
        )
    }

    func updateBundleId(id: String, name: String) async throws {
        guard let provider else {
            try await validateCredentials()
            return try await updateBundleId(id: id, name: name)
        }

        let body = BundleIDUpdateRequest(
            data: .init(
                type: .bundleIDs,
                id: id,
                attributes: .init(name: name)
            )
        )

        let endpoint = APIEndpoint.v1.bundleIDs.id(id).patch(body)
        _ = try await provider.request(endpoint)
        Log.print.info("[Apple] Renamed bundle identifier \(id)")
    }

    func deleteBundleId(id: String) async throws {
        guard let provider else {
            try await validateCredentials()
            return try await deleteBundleId(id: id)
        }

        let endpoint = APIEndpoint.v1.bundleIDs.id(id).delete
        _ = try await provider.request(endpoint)
        Log.print.info("[Apple] Deleted bundle identifier \(id)")
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
        guard let provider else {
            try await validateCredentials()
            return try await fetchBundleIdCapabilities(bundleId: bundleId)
        }

        // The /bundleIds/{id}/bundleIdCapabilities relationship rejects the `limit` query
        // ("PARAMETER_ERROR.ILLEGAL: This relationship does not support this parameter."),
        // even though the SDK exposes it. Call without parameters and let the API page itself.
        let endpoint = Request<CapabilitiesRawResponse>(
            path: "/v1/bundleIds/\(bundleId)/bundleIdCapabilities",
            method: "GET",
            id: "stackconnect_bundleIdCapabilities_relationship"
        )

        let response = try await provider.request(endpoint)
        let models = response.data.compactMap { cap -> BundleIdentifierCapabilityModel? in
            guard let typeRaw = cap.attributes?.capabilityType, !typeRaw.isEmpty else { return nil }
            return BundleIdentifierCapabilityModel(id: cap.id, capabilityType: typeRaw)
        }
        Log.print.info("[Apple] Fetched \(models.count) capabilities for \(bundleId)")
        return models
    }

    func enableCapability(bundleId: String, capabilityTypeRaw: String) async throws -> BundleIdentifierCapabilityModel {
        guard let provider else {
            try await validateCredentials()
            return try await enableCapability(bundleId: bundleId, capabilityTypeRaw: capabilityTypeRaw)
        }

        guard let type = CapabilityType(rawValue: capabilityTypeRaw) else {
            throw NSError(domain: "Capability", code: 400, userInfo: [NSLocalizedDescriptionKey: "Unsupported capability: \(capabilityTypeRaw)"])
        }

        let body = BundleIDCapabilityCreateRequest(
            data: .init(
                type: .bundleIDCapabilities,
                attributes: .init(capabilityType: type),
                relationships: .init(
                    bundleID: .init(data: .init(type: .bundleIDs, id: bundleId))
                )
            )
        )

        let endpoint = APIEndpoint.v1.bundleIDCapabilities.post(body)
        let response = try await provider.request(endpoint)
        let cap = response.data

        Log.print.info("[Apple] Enabled capability \(capabilityTypeRaw) on \(bundleId)")
        return BundleIdentifierCapabilityModel(
            id: cap.id,
            capabilityType: cap.attributes?.capabilityType?.rawValue ?? capabilityTypeRaw
        )
    }

    func disableCapability(capabilityId: String) async throws {
        guard let provider else {
            try await validateCredentials()
            return try await disableCapability(capabilityId: capabilityId)
        }

        let endpoint = APIEndpoint.v1.bundleIDCapabilities.id(capabilityId).delete
        _ = try await provider.request(endpoint)
        Log.print.info("[Apple] Disabled capability \(capabilityId)")
    }

    // MARK: - Devices

    func fetchDevices() async throws -> [DeviceModel] {
        guard let provider else {
            try await validateCredentials()
            return try await fetchDevices()
        }

        let endpoint = APIEndpoint
            .v1
            .devices
            .get(parameters: .init(sort: [.name], limit: 200))

        let response = try await provider.request(endpoint)
        let models = response.data.map { device in
            DeviceModel(
                id: device.id,
                name: device.attributes?.name ?? "",
                udid: device.attributes?.udid,
                platform: device.attributes?.platform?.rawValue,
                deviceClass: device.attributes?.deviceClass?.rawValue,
                model: device.attributes?.model,
                status: device.attributes?.status?.rawValue ?? "ENABLED",
                addedDate: device.attributes?.addedDate
            )
        }
        Log.print.info("[Apple] Fetched \(models.count) devices")
        return models
    }

    func createDevice(
        name: String,
        platformRaw: String,
        udid: String
    ) async throws -> DeviceModel {
        guard let provider else {
            try await validateCredentials()
            return try await createDevice(name: name, platformRaw: platformRaw, udid: udid)
        }

        guard let platform = BundleIDPlatform(rawValue: platformRaw) else {
            throw NSError(domain: "Device", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid platform: \(platformRaw)"])
        }

        let body = DeviceCreateRequest(
            data: .init(
                type: .devices,
                attributes: .init(name: name, platform: platform, udid: udid)
            )
        )

        let endpoint = APIEndpoint.v1.devices.post(body)
        let response = try await provider.request(endpoint)
        let device = response.data

        Log.print.info("[Apple] Registered device \(udid) (\(name))")
        return DeviceModel(
            id: device.id,
            name: device.attributes?.name ?? name,
            udid: device.attributes?.udid ?? udid,
            platform: device.attributes?.platform?.rawValue ?? platformRaw,
            deviceClass: device.attributes?.deviceClass?.rawValue,
            model: device.attributes?.model,
            status: device.attributes?.status?.rawValue ?? "ENABLED",
            addedDate: device.attributes?.addedDate
        )
    }

    func updateDevice(id: String, name: String?, status: String?) async throws {
        guard let provider else {
            try await validateCredentials()
            return try await updateDevice(id: id, name: name, status: status)
        }

        let statusEnum: DeviceUpdateRequest.Data.Attributes.Status? = status.flatMap {
            DeviceUpdateRequest.Data.Attributes.Status(rawValue: $0)
        }

        let body = DeviceUpdateRequest(
            data: .init(
                type: .devices,
                id: id,
                attributes: .init(name: name, status: statusEnum)
            )
        )

        let endpoint = APIEndpoint.v1.devices.id(id).patch(body)
        _ = try await provider.request(endpoint)
        Log.print.info("[Apple] Updated device \(id)")
    }

    // MARK: - Provisioning Profiles

    func fetchProfiles() async throws -> [ProvisioningProfileModel] {
        guard let provider else {
            try await validateCredentials()
            return try await fetchProfiles()
        }

        let endpoint = APIEndpoint
            .v1
            .profiles
            .get(parameters: .init(
                sort: [.name],
                limit: 200,
                include: [.bundleID]
            ))

        let response = try await provider.request(endpoint)

        var bundleIdentifierById: [String: String] = [:]
        for item in response.included ?? [] {
            if case .bundleID(let bundle) = item {
                bundleIdentifierById[bundle.id] = bundle.attributes?.identifier
            }
        }

        let models = response.data.map { profile -> ProvisioningProfileModel in
            let bundleRelId = profile.relationships?.bundleID?.data?.id
            let bundleIdentifier = bundleRelId.flatMap { bundleIdentifierById[$0] }

            return ProvisioningProfileModel(
                id: profile.id,
                name: profile.attributes?.name ?? "",
                profileType: profile.attributes?.profileType?.rawValue ?? "",
                profileState: profile.attributes?.profileState?.rawValue ?? "",
                platform: profile.attributes?.platform?.rawValue,
                uuid: profile.attributes?.uuid,
                bundleId: bundleIdentifier,
                createdDate: profile.attributes?.createdDate,
                expirationDate: profile.attributes?.expirationDate
            )
        }

        Log.print.info("[Apple] Fetched \(models.count) provisioning profiles")
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
        guard let provider else {
            try await validateCredentials()
            return try await createProfile(
                name: name,
                profileTypeRaw: profileTypeRaw,
                bundleIdId: bundleIdId,
                certificateIds: certificateIds,
                deviceIds: deviceIds
            )
        }

        guard let typeEnum = ProfileCreateRequest.Data.Attributes.ProfileType(rawValue: profileTypeRaw) else {
            throw NSError(domain: "Profiles", code: 400, userInfo: [NSLocalizedDescriptionKey: "Unsupported profile type: \(profileTypeRaw)"])
        }

        let devicesRel: ProfileCreateRequest.Data.Relationships.Devices? = deviceIds.isEmpty
            ? nil
            : .init(data: deviceIds.map { .init(type: .devices, id: $0) })

        let body = ProfileCreateRequest(
            data: .init(
                type: .profiles,
                attributes: .init(name: name, profileType: typeEnum),
                relationships: .init(
                    bundleID: .init(data: .init(type: .bundleIDs, id: bundleIdId)),
                    devices: devicesRel,
                    certificates: .init(data: certificateIds.map { .init(type: .certificates, id: $0) })
                )
            )
        )

        let endpoint = APIEndpoint.v1.profiles.post(body)
        let response = try await provider.request(endpoint)
        let profile = response.data

        let model = ProvisioningProfileModel(
            id: profile.id,
            name: profile.attributes?.name ?? name,
            profileType: profile.attributes?.profileType?.rawValue ?? profileTypeRaw,
            profileState: profile.attributes?.profileState?.rawValue ?? "ACTIVE",
            platform: profile.attributes?.platform?.rawValue,
            uuid: profile.attributes?.uuid,
            bundleId: nil,
            createdDate: profile.attributes?.createdDate,
            expirationDate: profile.attributes?.expirationDate
        )

        Log.print.info("[Apple] Created profile \(model.id) (\(profileTypeRaw))")
        return CreatedProfile(profile: model, content: profile.attributes?.profileContent)
    }

    func deleteProfile(id: String) async throws {
        guard let provider else {
            try await validateCredentials()
            return try await deleteProfile(id: id)
        }

        let endpoint = APIEndpoint.v1.profiles.id(id).delete
        _ = try await provider.request(endpoint)
        Log.print.info("[Apple] Deleted profile \(id)")
    }

    func fetchProfileContent(id: String) async throws -> String? {
        guard let provider else {
            try await validateCredentials()
            return try await fetchProfileContent(id: id)
        }

        let endpoint = APIEndpoint
            .v1
            .profiles
            .id(id)
            .get(parameters: .init(fieldsProfiles: [.profileContent, .name, .profileType, .platform, .profileState, .uuid, .createdDate, .expirationDate]))

        let response = try await provider.request(endpoint)
        return response.data.attributes?.profileContent
    }

    // MARK: - Private

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

    private static func mapVersion(_ version: AppStoreConnect_Swift_SDK.AppStoreVersion, appId: String) -> AppStoreVersionModel {
        let platformRaw = version.attributes?.platform?.rawValue
        let stateRaw = version.attributes?.appStoreState?.rawValue

        return AppStoreVersionModel(
            id: version.id,
            platform: platformRaw.flatMap { AppPlatform(rawValue: $0) },
            appStoreState: stateRaw.flatMap { AppStoreState(rawValue: $0) },
            appVersionState: version.attributes?.appVersionState?.rawValue,
            versionString: version.attributes?.versionString,
            copyright: version.attributes?.copyright,
            releaseType: version.attributes?.releaseType?.rawValue,
            createdDate: version.attributes?.createdDate,
            appId: appId
        )
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

    private func createProvider() throws -> APIProvider {
        let config = try APIConfiguration(
            issuerID: credentials.issuerID,
            privateKeyID: credentials.privateKeyID,
            privateKey: credentials.privateKey
        )
        return APIProvider(configuration: config)
    }

    /// Builds the Swift SDK `APIProvider` from the stored credentials and assigns it
    /// to `self.provider`. Network-free (`createProvider()` only constructs the
    /// `APIConfiguration`/`APIProvider`). Called by the Rust-core `validateCredentials()`
    /// path so the not-yet-migrated Swift-only fetch methods find a non-nil provider
    /// and stop recursing into `validateCredentials()` (issue #84).
    ///
    /// Internal (not private) purely so `RustCoreStranglerTests` can drive it in
    /// isolation from the network `Provider.validate()` call.
    func establishSwiftProvider() throws {
        self.provider = try createProvider()
    }

    // MARK: - Rust core (strangler path)

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
                store: rustCredentialStore
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

// MARK: - ImageAsset

private extension ImageAsset {
    func toIconUrl() -> String? {
        templateURL?
            .replacingOccurrences(of: "{w}", with: "\(width ?? 512)")
            .replacingOccurrences(of: "{h}", with: "\(height ?? 512)")
            .replacingOccurrences(of: "{f}", with: "png")
    }
}
