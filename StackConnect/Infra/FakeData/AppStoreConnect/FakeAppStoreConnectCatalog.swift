#if DEBUG
import Foundation
import StackCoreRust

/// Expands the App Store Connect seeds (`FakeAppStoreConnectSeeds.swift`) into
/// coherent in-memory teams: every version gets its build, localizations,
/// screenshots, review contact and submission history; every app gets
/// TestFlight groups and testers, reviews, app info, an age rating,
/// accessibility declarations, analytics reports and a bundle ID with a profile.
enum FakeAppStoreConnectCatalog {

    /// Name the fake API key's submissions are attributed to.
    static let apiKeyUserName = "StackConnect API Key"

    static func makeTeams(clock: FakeClock) -> [FakeAppStoreConnectTeam] {
        teamSeeds.map { seed in
            FakeAppStoreConnectTeam(issuerId: seed.issuerId, name: seed.name, clock: clock,
                                    state: makeState(team: seed, clock: clock))
        }
    }

    /// Every seeded app, for lookups by other fakes (rating summaries).
    static var allAppSeeds: [FakeASCAppSeed] {
        teamSeeds.flatMap(\.apps)
    }

    static func iconURL(for app: FakeASCAppSeed) -> String {
        FakeMedia.iconURL(name: app.name, symbol: app.symbol, color: app.color)
    }

    // MARK: - Team

    static func makeState(team: FakeASCTeamSeed, clock: FakeClock) -> FakeAppStoreConnectState {
        var state = FakeAppStoreConnectState()
        state.categories = categories

        // People
        let internalTesters: [BetaTesterInfo] = team.people.filter { $0.isTester && !$0.isPending }.enumerated().map { index, person in
            BetaTesterInfo(id: "tester-\(slug(team.name))-\(index)", firstName: person.firstName, lastName: person.lastName,
                           email: person.email, inviteType: "EMAIL", state: index.isMultiple(of: 3) ? "ACCEPTED" : "INSTALLED")
        }
        for (index, person) in team.people.enumerated() {
            let userId = "user-\(slug(team.name))-\(index)"
            state.users.append(UserInfo(
                id: userId, firstName: person.firstName, lastName: person.lastName, email: person.email,
                roles: person.roles, allAppsVisible: person.allAppsVisible,
                provisioningAllowed: person.provisioningAllowed, isPending: person.isPending,
                expirationDate: person.isPending ? clock.iso(daysFromNow: Double(12 + index)) : nil
            ))
            if !person.allAppsVisible {
                state.userVisibleApps[userId] = person.visibleAppIds
            }
            if !person.isPending {
                state.teamMembers.append(TeamMemberInfo(id: userId, firstName: person.firstName, lastName: person.lastName,
                                                        username: person.email, roles: person.roles))
            }
        }

        // Devices
        state.devices = team.devices.enumerated().map { index, device in
            DeviceInfo(id: "device-\(slug(team.name))-\(index)", name: device.name, udid: udid(seed: "\(team.teamId)-\(index)", deviceClass: device.deviceClass),
                       platform: device.platform, deviceClass: device.deviceClass, model: device.model,
                       status: device.status, addedDate: clock.iso(daysAgo: device.addedDaysAgo))
        }

        // Certificates
        state.certificates = team.certificates.enumerated().map { index, seed in
            let name = certificateDisplayName(type: seed.type, team: seed.owner)
            let serial = String(format: "%016llX", UInt64(abs(hash("\(team.teamId)-cert-\(index)"))))
            return CertificateInfo(
                id: "cert-\(slug(team.name))-\(index)", displayName: name, name: name, certificateType: seed.type,
                platform: seed.type.hasPrefix("MAC") || seed.type.hasPrefix("DEVELOPER_ID") ? "MAC_OS" : "IOS",
                serialNumber: serial, expirationDate: clock.iso(daysFromNow: seed.expiresInDays),
                isActivated: true, certificateContent: fakeDERBase64(seed: serial)
            )
        }

        // Apps
        for app in team.apps {
            addApp(app, team: team, to: &state, clock: clock, internalTesters: internalTesters)
        }

        // A wildcard App ID and a development profile covering every device.
        let wildcard = BundleIdInfo(id: "bundle-\(slug(team.name))-wildcard", identifier: "\(reverseDomain(team)).*",
                                    name: "\(team.name) Wildcard", platform: "UNIVERSAL", seedId: team.teamId)
        state.bundleIds.append(wildcard)
        state.profiles.append(ProvisioningProfileInfo(
            id: "profile-\(slug(team.name))-dev", name: "\(team.name) Team Development", profileType: "IOS_APP_DEVELOPMENT",
            profileState: "ACTIVE", platform: "IOS", uuid: uuid(seed: "\(team.teamId)-dev"), bundleId: wildcard.identifier,
            createdDate: clock.iso(daysAgo: 64), expirationDate: clock.iso(daysFromNow: 301),
            profileContent: fakeDERBase64(seed: "\(team.teamId)-dev")
        ))
        return state
    }

    // MARK: - App

    private static func addApp(
        _ app: FakeASCAppSeed,
        team: FakeASCTeamSeed,
        to state: inout FakeAppStoreConnectState,
        clock: FakeClock,
        internalTesters: [BetaTesterInfo]
    ) {
        let appSlug = slug(app.name)
        let primaryPlatform = app.versions.first?.platform ?? "IOS"
        let icon = iconURL(for: app)
        state.apps.append(AppInfo(id: app.id, name: app.name, bundleId: app.bundleId, platform: primaryPlatform))
        state.iconUrls[app.id] = icon

        // Versions, their builds and everything hanging off them.
        let newestByPlatform = Dictionary(grouping: app.versions, by: \.platform).compactMapValues { versions in
            versions.min { $0.createdDaysAgo < $1.createdDaysAgo }?.version
        }
        for seed in app.versions {
            let versionId = "ver-\(appSlug)-\(slug(seed.platform))-\(seed.version)"
            state.versions[app.id, default: []].append(AppStoreVersionInfo(
                id: versionId, appId: app.id, platform: seed.platform, appStoreState: seed.state,
                appVersionState: appVersionState(for: seed.state), versionString: seed.version,
                copyright: "© \(Calendar.current.component(.year, from: clock.date(daysAgo: seed.createdDaysAgo))) \(team.name)",
                releaseType: seed.releaseType, createdDate: clock.iso(daysAgo: seed.createdDaysAgo)
            ))

            let build = makeBuild(app: app, platform: seed.platform, marketingVersion: seed.version, number: seed.build,
                                  uploadedDaysAgo: seed.createdDaysAgo + 0.4, icon: icon, clock: clock, betaReview: "APPROVED")
            state.builds[app.id, default: []].append(build)
            state.versionBuilds[versionId] = build.id
            state.betaBuildLocalizations[build.id] = [
                BetaBuildLocalizationInfo(id: "bbl-\(build.id)", locale: "en-US",
                                          whatsNew: whatToTestNotes(app: app, version: seed.version))
            ]

            let isNewest = newestByPlatform[seed.platform] == seed.version
            state.versionLocalizations[versionId] = app.texts.enumerated().map { index, entry in
                let localizationId = "loc-\(versionId)-\(entry.locale)"
                state.screenshotSets[localizationId] = screenshotSets(app: app, platform: seed.platform,
                                                                      localizationId: localizationId, primary: index == 0)
                return AppStoreLocalizationInfo(
                    id: localizationId, locale: entry.locale, description: entry.text.description,
                    keywords: entry.text.keywords, promotionalText: entry.text.promotionalText,
                    supportUrl: "https://\(appSlug).northwind.example/support",
                    marketingUrl: "https://\(appSlug).northwind.example",
                    whatsNew: isNewest ? entry.text.whatsNew : olderWhatsNew(locale: entry.locale)
                )
            }

            state.appReviewDetails[versionId] = AppReviewDetailInfo(
                id: "ard-\(versionId)", contactFirstName: team.people.first?.firstName,
                contactLastName: team.people.first?.lastName,
                contactEmail: "app-review@\(team.apps.count > 2 ? "northwind" : "mail").example",
                contactPhone: "+1 415 555 0142",
                notes: "Sign in with the demo account below. Premium features are unlocked for it. Location permission is only needed for live tracking; you can deny it and use the sample routes.",
                demoAccountName: "review@\(appSlug).example", demoAccountPassword: "Review-2026!",
                isDemoAccountRequired: true
            )

            if let day = seed.phasedDay {
                state.phasedReleases[versionId] = PhasedReleaseInfo(
                    id: "phased-\(versionId)", state: "ACTIVE",
                    startDate: clock.iso(daysAgo: Double(day - 1), hoursAgo: 3),
                    totalPauseDuration: 0, currentDayNumber: Int32(day)
                )
            } else if seed.state == "PENDING_DEVELOPER_RELEASE" {
                state.phasedReleases[versionId] = PhasedReleaseInfo(
                    id: "phased-\(versionId)", state: "INACTIVE", startDate: nil, totalPauseDuration: 0, currentDayNumber: 0
                )
            }

            if let submitted = seed.submittedDaysAgo {
                state.submissions[app.id, default: []].append(ReviewSubmission(
                    id: "sub-\(versionId)", appId: app.id, platform: seed.platform,
                    submittedDate: clock.iso(daysAgo: submitted), state: submissionState(for: seed.state),
                    versionString: seed.version, versionId: versionId,
                    submittedByName: submitted < 3 ? apiKeyUserName : team.people.first.map { "\($0.firstName) \($0.lastName)" },
                    submittedByEmail: submitted < 3 ? nil : team.people.first?.email
                ))
            }
        }

        // TestFlight builds of the next version, groups and testers.
        addTestFlight(app: app, team: team, primaryPlatform: primaryPlatform, icon: icon, to: &state,
                      clock: clock, internalTesters: internalTesters)

        // Reviews
        state.reviews[app.id] = app.reviews.enumerated().map { index, review in
            CustomerReview(
                id: "review-\(appSlug)-\(index)", rating: review.rating, title: review.title, body: review.body,
                reviewerNickname: review.nickname, createdDate: clock.iso(daysAgo: review.daysAgo),
                territory: review.territory,
                response: review.reply.map { reply in
                    ReviewResponse(id: "resp-\(appSlug)-\(index)", body: reply,
                                   state: review.replyPending ? "PENDING_PUBLISH" : "PUBLISHED",
                                   lastModifiedDate: clock.iso(daysAgo: max(review.daysAgo - 0.5, 0.05)))
                }
            )
        }

        // App info, age rating, privacy
        let ageRatingId = "age-\(appSlug)"
        state.appInfos[app.id] = AppInfoDetails(
            appInfoId: "appinfo-\(appSlug)", appId: app.id, sku: app.sku, primaryLocale: app.texts.first?.locale ?? "en-US",
            contentRightsDeclaration: "DOES_NOT_USE_THIRD_PARTY_CONTENT",
            primaryCategoryId: app.primaryCategory, primarySubcategoryOneId: app.primarySubcategory,
            secondaryCategoryId: app.secondaryCategory, secondarySubcategoryOneId: nil,
            ageRatingDeclarationId: ageRatingId, appStoreAgeRating: app.appStoreAgeRating,
            localizations: app.texts.map { entry in
                AppInfoLocalizationInfo(
                    id: "ail-\(appSlug)-\(entry.locale)", locale: entry.locale, name: entry.text.name, subtitle: entry.text.subtitle,
                    privacyPolicyUrl: "https://\(appSlug).northwind.example/privacy",
                    privacyChoicesUrl: "https://\(appSlug).northwind.example/privacy/choices",
                    privacyPolicyText: nil
                )
            },
            ageRating: ageRating(id: ageRatingId, answers: app.ageRatingAnswers)
        )

        // Accessibility
        var families = [deviceFamily(for: primaryPlatform)]
        if app.hasIPad, primaryPlatform == "IOS" { families.append("IPAD") }
        for platform in Set(app.versions.map(\.platform)) where platform != primaryPlatform {
            families.append(deviceFamily(for: platform))
        }
        state.accessibility[app.id] = families.enumerated().map { index, family in
            AccessibilityDeclarationInfo(
                id: "a11y-\(appSlug)-\(family.lowercased())", deviceFamily: family, state: index == 0 ? "PUBLISHED" : "DRAFT",
                supportsAudioDescriptions: false, supportsCaptions: family != "APPLE_TV", supportsDarkInterface: true,
                supportsDifferentiateWithoutColor: true, supportsLargerText: family != "APPLE_TV",
                supportsReducedMotion: true, supportsSufficientContrast: true,
                supportsVoiceControl: index == 0, supportsVoiceover: true
            )
        }

        // Provisioning: App ID, capabilities, App Store profile
        let bundleRecordId = "bundle-\(appSlug)"
        state.bundleIds.append(BundleIdInfo(id: bundleRecordId, identifier: app.bundleId, name: app.name,
                                            platform: primaryPlatform == "MAC_OS" ? "MAC_OS" : "IOS", seedId: team.teamId))
        state.bundleCapabilities[bundleRecordId] = app.capabilities.map {
            BundleIdCapabilityInfo(id: "\(bundleRecordId)_\($0)", capabilityType: $0)
        }
        let profileType: String
        switch primaryPlatform {
        case "MAC_OS": profileType = "MAC_APP_STORE"
        case "TV_OS":  profileType = "TVOS_APP_STORE"
        default:       profileType = "IOS_APP_STORE"
        }
        state.profiles.append(ProvisioningProfileInfo(
            id: "profile-\(appSlug)-store", name: "\(app.name) App Store", profileType: profileType, profileState: "ACTIVE",
            platform: primaryPlatform == "MAC_OS" ? "MAC_OS" : "IOS", uuid: uuid(seed: "\(app.id)-store"), bundleId: app.bundleId,
            createdDate: clock.iso(daysAgo: 150), expirationDate: clock.iso(daysFromNow: 215),
            profileContent: fakeDERBase64(seed: "\(app.id)-store")
        ))
        if app.id == trailhead.id {
            state.profiles.append(ProvisioningProfileInfo(
                id: "profile-\(appSlug)-adhoc", name: "\(app.name) Ad Hoc (Field Test)", profileType: "IOS_APP_ADHOC",
                profileState: "INVALID", platform: "IOS", uuid: uuid(seed: "\(app.id)-adhoc"), bundleId: app.bundleId,
                createdDate: clock.iso(daysAgo: 410), expirationDate: clock.iso(daysAgo: 45),
                profileContent: fakeDERBase64(seed: "\(app.id)-adhoc")
            ))
        }

        // Analytics: one ongoing request with every catalog report.
        _ = addAnalytics(to: &state, app: AppInfo(id: app.id, name: app.name, bundleId: app.bundleId, platform: primaryPlatform),
                         accessType: "ONGOING", clock: clock)
    }

    // MARK: - TestFlight

    private static func addTestFlight(
        app: FakeASCAppSeed,
        team: FakeASCTeamSeed,
        primaryPlatform: String,
        icon: String,
        to state: inout FakeAppStoreConnectState,
        clock: FakeClock,
        internalTesters: [BetaTesterInfo]
    ) {
        let appSlug = slug(app.name)
        var betaBuildIds: [String] = []
        if let testFlight = app.testFlight {
            for (index, number) in testFlight.builds.enumerated() {
                // Oldest: approved and in testing; last: still processing;
                // in between: waiting for beta app review.
                let isLast = index == testFlight.builds.count - 1
                let betaReview: String? = isLast ? nil : (index == 0 ? "APPROVED" : "WAITING_FOR_REVIEW")
                let build = makeBuild(app: app, platform: primaryPlatform, marketingVersion: testFlight.version, number: number,
                                      uploadedDaysAgo: Double(testFlight.builds.count - index) * 1.7 - 1.2,
                                      icon: icon, clock: clock, betaReview: betaReview, processing: isLast)
                state.builds[app.id, default: []].append(build)
                betaBuildIds.append(build.id)
                state.betaBuildLocalizations[build.id] = [
                    BetaBuildLocalizationInfo(id: "bbl-\(build.id)", locale: "en-US", whatsNew: testFlight.whatToTest)
                ]
            }
        }

        let allBuildIds = (state.builds[app.id] ?? []).filter { $0.expired != true && $0.processingState == "VALID" }.map(\.id)
        let internalGroup = BetaGroupInfo(
            id: "group-\(appSlug)-internal", appId: app.id, name: "\(team.name.split(separator: " ").first ?? "Team") QA",
            createdDate: clock.iso(daysAgo: 300), isInternalGroup: true, hasAccessToAllBuilds: true,
            publicLinkEnabled: false, publicLink: nil, feedbackEnabled: true
        )
        state.betaGroups[app.id, default: []].append(internalGroup)
        state.groupTesters[internalGroup.id] = internalTesters.map { tester in
            var copy = tester
            copy.id = "\(tester.id)-\(appSlug)"
            return copy
        }
        state.groupBuildIds[internalGroup.id] = allBuildIds

        guard let testFlight = app.testFlight else { return }

        let externalGroup = BetaGroupInfo(
            id: "group-\(appSlug)-external", appId: app.id, name: testFlight.externalGroupName,
            createdDate: clock.iso(daysAgo: 190), isInternalGroup: false, hasAccessToAllBuilds: false,
            publicLinkEnabled: true, publicLink: "https://testflight.fakedata.example/join/\(appSlug.prefix(4))\(app.id.suffix(4))",
            feedbackEnabled: true
        )
        let partnersGroup = BetaGroupInfo(
            id: "group-\(appSlug)-partners", appId: app.id, name: "Press & Partners",
            createdDate: clock.iso(daysAgo: 95), isInternalGroup: false, hasAccessToAllBuilds: false,
            publicLinkEnabled: false, publicLink: nil, feedbackEnabled: false
        )
        state.betaGroups[app.id]?.append(contentsOf: [externalGroup, partnersGroup])

        let states = ["INSTALLED", "INSTALLED", "ACCEPTED", "INVITED", "INSTALLED", "ACCEPTED", "INSTALLED", "INVITED", "INSTALLED", "ACCEPTED"]
        state.groupTesters[externalGroup.id] = externalTesters.enumerated().map { index, person in
            BetaTesterInfo(id: "tester-\(appSlug)-ext-\(index)", firstName: person.first, lastName: person.last, email: person.email,
                           inviteType: index.isMultiple(of: 3) ? "PUBLIC_LINK" : "EMAIL", state: states[index % states.count])
        }
        state.groupTesters[partnersGroup.id] = externalTesters.suffix(3).enumerated().map { index, person in
            BetaTesterInfo(id: "tester-\(appSlug)-press-\(index)", firstName: person.first, lastName: person.last, email: person.email,
                           inviteType: "EMAIL", state: index == 0 ? "INVITED" : "ACCEPTED")
        }
        let approvedBetas = betaBuildIds.filter { id in state.build(id)?.betaReviewState == "APPROVED" }
        state.groupBuildIds[externalGroup.id] = approvedBetas
        state.groupBuildIds[partnersGroup.id] = Array(approvedBetas.suffix(1))

        state.betaAppLocalizations[app.id] = [
            BetaAppLocalizationInfo(id: "bal-\(appSlug)-en", locale: "en-US", feedbackEmail: "beta@\(appSlug).northwind.example",
                                    description: "Thanks for testing \(app.name)! Builds land here a few days before they reach the App Store. Shake the device or take a screenshot to send feedback.")
        ]
        state.betaAppReviewDetails[app.id] = BetaAppReviewDetailInfo(
            id: "bard-\(appSlug)", contactFirstName: team.people.first?.firstName, contactLastName: team.people.first?.lastName,
            contactEmail: "beta-review@northwind.example", contactPhone: "+1 415 555 0142",
            demoAccountName: "beta@\(appSlug).example", demoAccountPassword: "Beta-2026!",
            isDemoAccountRequired: true,
            notes: "The beta adds \(testFlight.whatToTest.split(separator: ":").first ?? "new features"). Use the demo account to skip onboarding."
        )
    }

    private static func makeBuild(
        app: FakeASCAppSeed,
        platform: String,
        marketingVersion: String,
        number: String,
        uploadedDaysAgo: Double,
        icon: String,
        clock: FakeClock,
        betaReview: String?,
        processing: Bool = false
    ) -> BuildInfo {
        let approved = betaReview == "APPROVED"
        let uploaded = clock.date(daysAgo: max(uploadedDaysAgo, 0.05))
        let expiration = uploaded.addingTimeInterval(90 * 86_400)
        let isExpired = expiration < clock.now
        let externalState: String
        if processing {
            externalState = "PROCESSING"
        } else if isExpired {
            externalState = "EXPIRED"
        } else if approved {
            externalState = "IN_BETA_TESTING"
        } else if betaReview == "WAITING_FOR_REVIEW" {
            externalState = "WAITING_FOR_BETA_REVIEW"
        } else {
            externalState = "READY_FOR_BETA_SUBMISSION"
        }
        return BuildInfo(
            id: "build-\(slug(app.name))-\(slug(platform))-\(number)", appId: app.id, version: number,
            uploadedDate: FakeClock.iso(uploaded), expired: isExpired,
            processingState: processing ? "PROCESSING" : "VALID",
            minOsVersion: minimumOS(for: platform), expirationDate: FakeClock.iso(expiration),
            marketingVersion: marketingVersion, platform: platform,
            externalBuildState: externalState,
            internalBuildState: processing ? "PROCESSING" : (isExpired ? "EXPIRED" : "IN_BETA_TESTING"),
            autoNotifyEnabled: true,
            betaReviewState: processing ? nil : betaReview,
            submittedDate: betaReview != nil ? FakeClock.iso(uploaded.addingTimeInterval(3 * 3_600)) : nil,
            computedMinMacOsVersion: platform == "MAC_OS" ? "14.0" : (platform == "IOS" ? "14.0" : nil),
            computedMinVisionOsVersion: platform == "VISION_OS" ? "1.0" : (platform == "IOS" ? "1.0" : nil),
            buildAudienceType: "APP_STORE_ELIGIBLE", usesNonExemptEncryption: false, iconUrl: icon
        )
    }

    // MARK: - Analytics

    /// Adds an analytics report request (with every catalog report, a few
    /// daily / weekly / monthly instances and one segment each) for `app`.
    @discardableResult
    static func addAnalytics(
        to state: inout FakeAppStoreConnectState,
        app: AppInfo,
        accessType: String,
        clock: FakeClock
    ) -> AnalyticsReportRequest {
        let requestId = "arr-\(slug(app.name))-\(accessType.lowercased())-\((state.analyticsRequests[app.id] ?? []).count)"
        let request = AnalyticsReportRequest(id: requestId, accessType: accessType, stoppedDueToInactivity: false)
        state.analyticsRequests[app.id, default: []].append(request)

        var reports: [AnalyticsReport] = []
        for section in AnalyticsCatalog.sections {
            for report in section.reports {
                let reportId = "\(requestId)-\(slug(report.apiName))"
                reports.append(AnalyticsReport(id: reportId, name: report.apiName, category: section.category.rawValue))
                var instances: [AnalyticsReportInstance] = []
                let schedule: [(String, [Double])] = [
                    ("DAILY", [1, 2, 3, 4, 5, 6, 7]),
                    ("WEEKLY", [3, 10, 17, 24]),
                    ("MONTHLY", [16, 46, 76])
                ]
                for (granularity, offsets) in schedule {
                    for offset in offsets {
                        let date = FakeClock.day(clock.date(daysAgo: offset))
                        let instanceId = "\(reportId)-\(granularity.lowercased())-\(date)"
                        instances.append(AnalyticsReportInstance(id: instanceId, granularity: granularity, processingDate: date))
                        let url = "https://analytics.fakedata.example/segments/\(instanceId).tsv.gz"
                        state.analyticsSegments[instanceId] = [
                            AnalyticsReportSegment(id: "\(instanceId)-seg", url: url, checksum: String(abs(hash(instanceId)) & 0xffff_ffff, radix: 16),
                                                   sizeInBytes: Int64(4_096 + abs(hash(url)) % 60_000))
                        ]
                        state.segmentSources[url] = .init(appName: app.name, reportName: report.apiName,
                                                          granularity: granularity, processingDate: date)
                    }
                }
                state.analyticsInstances[reportId] = instances
            }
        }
        state.analyticsReports[requestId] = reports
        return request
    }

    // MARK: - Pieces

    static let categories: [AppCategoryInfo] = [
        AppCategoryInfo(id: "BOOKS", subcategoryIds: []),
        AppCategoryInfo(id: "BUSINESS", subcategoryIds: []),
        AppCategoryInfo(id: "DEVELOPER_TOOLS", subcategoryIds: []),
        AppCategoryInfo(id: "EDUCATION", subcategoryIds: []),
        AppCategoryInfo(id: "ENTERTAINMENT", subcategoryIds: []),
        AppCategoryInfo(id: "FINANCE", subcategoryIds: []),
        AppCategoryInfo(id: "FOOD_AND_DRINK", subcategoryIds: []),
        AppCategoryInfo(id: "GAMES", subcategoryIds: ["GAMES_ACTION", "GAMES_ADVENTURE", "GAMES_BOARD", "GAMES_CASUAL", "GAMES_PUZZLE", "GAMES_STRATEGY", "GAMES_WORD"]),
        AppCategoryInfo(id: "HEALTH_AND_FITNESS", subcategoryIds: []),
        AppCategoryInfo(id: "LIFESTYLE", subcategoryIds: []),
        AppCategoryInfo(id: "MUSIC", subcategoryIds: []),
        AppCategoryInfo(id: "NAVIGATION", subcategoryIds: []),
        AppCategoryInfo(id: "NEWS", subcategoryIds: []),
        AppCategoryInfo(id: "PHOTO_AND_VIDEO", subcategoryIds: []),
        AppCategoryInfo(id: "PRODUCTIVITY", subcategoryIds: []),
        AppCategoryInfo(id: "REFERENCE", subcategoryIds: []),
        AppCategoryInfo(id: "SOCIAL_NETWORKING", subcategoryIds: []),
        AppCategoryInfo(id: "SPORTS", subcategoryIds: []),
        AppCategoryInfo(id: "TRAVEL", subcategoryIds: []),
        AppCategoryInfo(id: "UTILITIES", subcategoryIds: []),
        AppCategoryInfo(id: "WEATHER", subcategoryIds: [])
    ]

    static func certificateDisplayName(type: String, team: String) -> String {
        switch type {
        case "DISTRIBUTION", "IOS_DISTRIBUTION": return "Apple Distribution: \(team)"
        case "DEVELOPMENT", "IOS_DEVELOPMENT":   return "Apple Development: \(team)"
        case "DEVELOPER_ID_APPLICATION":         return "Developer ID Application: \(team)"
        case "MAC_INSTALLER_DISTRIBUTION":       return "3rd Party Mac Developer Installer: \(team)"
        case "MAC_APP_DISTRIBUTION":             return "3rd Party Mac Developer Application: \(team)"
        default:                                 return "\(type.replacingOccurrences(of: "_", with: " ").capitalized): \(team)"
        }
    }

    /// Placeholder certificate / profile payload (base64, not a real DER).
    static func fakeDERBase64(seed: String) -> String {
        Data("FAKE-DATA-\(seed)-NOT-A-REAL-CERTIFICATE".utf8).base64EncodedString()
    }

    private static func screenshotSets(app: FakeASCAppSeed, platform: String, localizationId: String, primary: Bool) -> [ScreenshotSetInfo] {
        var types: [(String, Int, Int)]
        switch platform {
        case "MAC_OS":    types = [("APP_DESKTOP", 2880, 1800)]
        case "TV_OS":     types = [("APP_APPLE_TV", 3840, 2160)]
        case "VISION_OS": types = [("APP_APPLE_VISION_PRO", 3840, 2160)]
        default:
            types = [("APP_IPHONE_67", 1290, 2796)]
            if app.hasIPad { types.append(("APP_IPAD_PRO_3GEN_129", 2048, 2732)) }
        }
        return types.map { displayType, width, height in
            let captions = primary ? app.screenshotCaptions : Array(app.screenshotCaptions.prefix(2))
            return ScreenshotSetInfo(
                id: "sset-\(localizationId)-\(displayType.lowercased())", displayType: displayType,
                screenshots: captions.enumerated().map { index, caption in
                    ScreenshotInfo(
                        id: "shot-\(localizationId)-\(displayType.lowercased())-\(index)",
                        imageUrl: FakeMedia.screenshotURL(appName: app.name, symbol: app.symbol, color: app.color,
                                                          caption: caption, width: width, height: height),
                        fileName: "\(slug(app.name))_\(displayType.lowercased())_\(index + 1).png",
                        fileSize: Int32(900_000 + index * 73_000), width: Int32(width), height: Int32(height)
                    )
                }
            )
        }
    }

    private static func ageRating(id: String, answers: [String: String]) -> AgeRatingDeclarationInfo {
        func answer(_ key: String) -> String { answers[key] ?? "NONE" }
        return AgeRatingDeclarationInfo(
            id: id,
            alcoholTobaccoOrDrugUseOrReferences: answer("alcoholTobaccoOrDrugUseOrReferences"),
            contests: answer("contests"), gamblingSimulated: answer("gamblingSimulated"),
            gunsOrOtherWeapons: answer("gunsOrOtherWeapons"),
            medicalOrTreatmentInformation: answer("medicalOrTreatmentInformation"),
            profanityOrCrudeHumor: answer("profanityOrCrudeHumor"),
            sexualContentGraphicAndNudity: answer("sexualContentGraphicAndNudity"),
            sexualContentOrNudity: answer("sexualContentOrNudity"),
            horrorOrFearThemes: answer("horrorOrFearThemes"),
            matureOrSuggestiveThemes: answer("matureOrSuggestiveThemes"),
            violenceCartoonOrFantasy: answer("violenceCartoonOrFantasy"),
            violenceRealistic: answer("violenceRealistic"),
            violenceRealisticProlongedGraphicOrSadistic: answer("violenceRealisticProlongedGraphicOrSadistic"),
            isAdvertising: false, isGambling: false, isUnrestrictedWebAccess: false, isUserGeneratedContent: false,
            ageRatingOverrideV2: "NONE"
        )
    }

    private static func appVersionState(for appStoreState: String) -> String {
        switch appStoreState {
        case "READY_FOR_SALE":            return "READY_FOR_DISTRIBUTION"
        case "PENDING_DEVELOPER_RELEASE": return "PENDING_DEVELOPER_RELEASE"
        case "REJECTED":                  return "REJECTED"
        default:                          return appStoreState
        }
    }

    private static func submissionState(for appStoreState: String) -> String {
        switch appStoreState {
        case "WAITING_FOR_REVIEW": return "WAITING_FOR_REVIEW"
        case "IN_REVIEW":          return "IN_REVIEW"
        case "REJECTED", "METADATA_REJECTED": return "UNRESOLVED_ISSUES"
        default:                   return "COMPLETE"
        }
    }

    private static func deviceFamily(for platform: String) -> String {
        switch platform {
        case "MAC_OS":    return "MAC"
        case "TV_OS":     return "APPLE_TV"
        case "VISION_OS": return "VISION"
        default:          return "IPHONE"
        }
    }

    private static func minimumOS(for platform: String) -> String {
        switch platform {
        case "MAC_OS":    return "14.0"
        case "TV_OS":     return "17.0"
        case "VISION_OS": return "1.2"
        default:          return "17.0"
        }
    }

    private static func whatToTestNotes(app: FakeASCAppSeed, version: String) -> String {
        "Release candidate for \(app.name) \(version). Please run through sign-in, sync and the main flows before we submit."
    }

    private static func olderWhatsNew(locale: String) -> String {
        switch locale {
        case "pt-BR": return "Correções de bugs e melhorias de desempenho."
        case "de-DE": return "Fehlerbehebungen und Leistungsverbesserungen."
        case "fr-FR": return "Corrections de bugs et améliorations des performances."
        case "es-ES": return "Corrección de errores y mejoras de rendimiento."
        case "ja":    return "バグ修正とパフォーマンスの改善。"
        default:      return "Bug fixes and performance improvements."
        }
    }

    private static func reverseDomain(_ team: FakeASCTeamSeed) -> String {
        team.apps.first.map { $0.bundleId.split(separator: ".").prefix(2).joined(separator: ".") } ?? "com.example"
    }

    static func slug(_ text: String) -> String {
        text.lowercased().unicodeScalars
            .map { CharacterSet.alphanumerics.contains($0) && $0.isASCII ? String($0) : "-" }
            .joined()
            .split(separator: "-").joined(separator: "-")
    }

    /// Stable (per launch and across launches) hash of a string.
    static func hash(_ text: String) -> Int {
        var value: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in text.utf8 {
            value ^= UInt64(byte)
            value = value &* 0x100_0000_01b3
        }
        return Int(truncatingIfNeeded: value >> 1)
    }

    private static func uuid(seed: String) -> String {
        let hex = String(format: "%016llx%016llx", UInt64(abs(hash(seed))), UInt64(abs(hash(seed + "#"))))
        let chars = Array(hex.prefix(32))
        return "\(String(chars[0..<8]))-\(String(chars[8..<12]))-\(String(chars[12..<16]))-\(String(chars[16..<20]))-\(String(chars[20..<32]))"
    }

    private static func udid(seed: String, deviceClass: String) -> String {
        let hex = String(format: "%016llX%016llX", UInt64(abs(hash(seed))), UInt64(abs(hash(seed + "u"))))
        if deviceClass == "MAC" {
            return uuid(seed: seed).uppercased()
        }
        return "00008\(hex.prefix(3))-\(hex.dropFirst(3).prefix(16))"
    }
}

/// Builds the rows of a downloaded analytics segment: a TSV-like table whose
/// columns follow Apple's report of the same name, with deterministic numbers.
enum FakeAnalyticsReportGenerator {

    static func data(for source: FakeAppStoreConnectState.SegmentSource) -> AnalyticsReportData {
        var random = FakeRandom(seed: "\(source.appName)|\(source.reportName)|\(source.granularity)|\(source.processingDate)")
        let territories = ["US", "GB", "DE", "BR", "JP", "FR", "CA", "AU"]
        let devices = ["iPhone", "iPad", "Desktop", "Apple TV", "Apple Vision Pro"]
        let scale = source.granularity == "DAILY" ? 1 : (source.granularity == "WEEKLY" ? 7 : 30)
        let headers: [String]
        var rows: [[String]] = []

        switch source.reportName {
        case "App Store Downloads":
            headers = ["Date", "App Name", "Download Type", "App Version", "Device", "Territory", "Counts"]
            for territory in territories {
                for type in ["First-time download", "Redownload", "Auto-update"] {
                    rows.append([source.processingDate, source.appName, type, "4.2.0", devices[random.int(in: 0...1)], territory,
                                 String(random.int(in: 20...900) * scale)])
                }
            }
        case "App Sessions":
            headers = ["Date", "App Name", "App Version", "Device", "Territory", "Sessions", "Total Session Duration", "Unique Devices"]
            for territory in territories {
                let sessions = random.int(in: 300...6_000) * scale
                rows.append([source.processingDate, source.appName, "4.2.0", devices[random.int(in: 0...1)], territory,
                             String(sessions), String(sessions * random.int(in: 180...600)), String(sessions / random.int(in: 2...5))])
            }
        case "App Crashes":
            headers = ["Date", "App Name", "App Version", "Build", "Device", "Platform Version", "Crashes", "Unique Devices"]
            for version in ["18.6", "26.0", "26.1"] {
                for device in devices.prefix(2) {
                    let crashes = random.int(in: 0...40) * scale
                    rows.append([source.processingDate, source.appName, "4.2.0", "4210", device, version,
                                 String(crashes), String(max(crashes - random.int(in: 0...5), 0))])
                }
            }
        case "App Store Discovery and Engagement":
            headers = ["Date", "App Name", "Event", "Page Type", "Source Type", "Territory", "Counts", "Unique Counts"]
            for territory in territories.prefix(6) {
                for event in ["Impression", "Page view", "Tap"] {
                    let counts = random.int(in: 200...20_000) * scale
                    rows.append([source.processingDate, source.appName, event, "Product page", ["App Store search", "App Store browse", "Web referrer"][random.int(in: 0...2)],
                                 territory, String(counts), String(counts * 7 / 10)])
                }
            }
        default:
            headers = ["Date", "App Name", "Event", "Device", "Territory", "Counts", "Unique Devices"]
            for territory in territories.prefix(5) {
                let counts = random.int(in: 10...2_500) * scale
                rows.append([source.processingDate, source.appName, source.reportName, devices[random.int(in: 0...2)], territory,
                             String(counts), String(counts * 3 / 5)])
            }
        }
        return AnalyticsReportData(headers: headers, rows: rows, rowCount: UInt32(rows.count))
    }
}
#endif
