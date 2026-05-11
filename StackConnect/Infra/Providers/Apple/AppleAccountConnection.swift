import Foundation
import AppStoreConnect_Swift_SDK
import StackProtocols

final class AppleAccountConnection: AccountConnectionProtocol, @unchecked Sendable {

    private let credentials: AppleCredentials
    private var provider: APIProvider?

    init(credentials: AppleCredentials) {
        self.credentials = credentials
    }

    // MARK: - AccountConnectionProtocol

    func validateCredentials() async throws {
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
        guard let provider else {
            try await validateCredentials()
            return try await createAppStoreVersion(request: request)
        }

        let body = request.toSDKRequest()
        let endpoint = APIEndpoint.v1.appStoreVersions.post(body)
        let response = try await provider.request(endpoint)
        return Self.mapVersion(response.data, appId: request.appId)
    }

    func fetchAppStoreVersion(appId: String) async -> (state: String?, version: String?) {
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
                    include: [.preReleaseVersion]
                )
            )

        let response = try await provider.request(request)

        var platformByPreReleaseId: [String: String] = [:]
        for item in response.included ?? [] {
            if case .prereleaseVersion(let pre) = item,
               let platform = pre.attributes?.platform?.rawValue {
                platformByPreReleaseId[pre.id] = platform
            }
        }

        return response.data.map { build in
            let preReleaseId = build.relationships?.preReleaseVersion?.data?.id
            let platform = preReleaseId.flatMap { platformByPreReleaseId[$0] }
            return BuildModel(
                id: build.id,
                version: build.attributes?.version,
                processingState: build.attributes?.processingState?.rawValue,
                uploadedDate: build.attributes?.uploadedDate,
                iconUrl: build.attributes?.iconAssetToken?.toIconUrl(),
                platform: platform
            )
        }
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
                    include: [.preReleaseVersion]
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

        var platformByPreReleaseId: [String: String] = [:]
        for item in response.included ?? [] {
            if case .prereleaseVersion(let pre) = item,
               let platform = pre.attributes?.platform?.rawValue {
                platformByPreReleaseId[pre.id] = platform
            }
        }

        let builds = response.data.map { build -> BuildModel in
            let preReleaseId = build.relationships?.preReleaseVersion?.data?.id
            let platform = preReleaseId.flatMap { platformByPreReleaseId[$0] }
            return BuildModel(
                id: build.id,
                version: build.attributes?.version,
                processingState: build.attributes?.processingState?.rawValue,
                uploadedDate: build.attributes?.uploadedDate,
                iconUrl: build.attributes?.iconAssetToken?.toIconUrl(),
                platform: platform
            )
        }

        return BuildsPage(builds: builds, hasNextPage: response.links.next != nil, rawResponse: response)
    }

    func fetchCurrentBuild(versionId: String) async throws -> BuildModel? {
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

    func createBetaGroup(appId: String, name: String, isInternal: Bool, isPublicLinkEnabled: Bool = false) async throws -> BetaGroupModel {
        guard let provider else {
            try await validateCredentials()
            return try await createBetaGroup(appId: appId, name: name, isInternal: isInternal, isPublicLinkEnabled: isPublicLinkEnabled)
        }

        let body = BetaGroupCreateRequest(
            data: .init(
                type: .betaGroups,
                attributes: .init(
                    name: name,
                    isInternalGroup: isInternal,
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
        guard let provider else {
            try await validateCredentials()
            return try await fetchTesterCount(groupId: groupId)
        }

        let endpoint = APIEndpoint.v1.betaGroups.id(groupId).betaTesters.get(fieldsBetaTesters: [], limit: 1)
        let response = try await provider.request(endpoint)
        return response.meta?.paging.total ?? 0
    }

    func fetchBetaTestersForGroup(groupId: String) async throws -> [BetaTesterModel] {
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
                isPending: false
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
                isPending: true
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
                    include: [.preReleaseVersion]
                )
            )

        let response = try await provider.request(endpoint)

        var platformByPreReleaseId: [String: String] = [:]
        for item in response.included ?? [] {
            if case .prereleaseVersion(let pre) = item,
               let platform = pre.attributes?.platform?.rawValue {
                platformByPreReleaseId[pre.id] = platform
            }
        }

        return response.data.map { build in
            let preReleaseId = build.relationships?.preReleaseVersion?.data?.id
            let platform = preReleaseId.flatMap { platformByPreReleaseId[$0] }
            return BuildModel(
                id: build.id,
                version: build.attributes?.version,
                processingState: build.attributes?.processingState?.rawValue,
                uploadedDate: build.attributes?.uploadedDate,
                iconUrl: build.attributes?.iconAssetToken?.toIconUrl(),
                platform: platform
            )
        }
    }

    func addBuildToGroups(buildId: String, groupIds: [String]) async throws {
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

    private func createProvider() throws -> APIProvider {
        let config = try APIConfiguration(
            issuerID: credentials.issuerID,
            privateKeyID: credentials.privateKeyID,
            privateKey: credentials.privateKey
        )
        return APIProvider(configuration: config)
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
