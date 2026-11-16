#if DEBUG
import Foundation
import StackCoreRust

/// In-memory Google Play provider. Serves the same capabilities the real core
/// exposes for Play (`[.apps, .reviews, .appDetails, .storeListings, .tracks,
/// .appIcons, .releaseManagement, .playUsers]`) from one `FakeGooglePlayDeveloper`.
///
/// Extending it for a new Play capability: override the capability accessor
/// here, add a `FakePlay…` subclass of the core's handle below that overrides
/// **every** `open func` of that handle (an un-overridden method calls into Rust
/// with a null handle and crashes), and seed its data in `FakeGooglePlayCatalog`.
final class FakeGooglePlayProvider: FakeCoreProvider, @unchecked Sendable {

    private let developer: FakeGooglePlayDeveloper

    init(developer: FakeGooglePlayDeveloper) {
        self.developer = developer
        super.init(kind: .googlePlay)
    }

    required init(unsafeFromHandle handle: UInt64) {
        fatalError("Fake core providers are never lifted from the FFI")
    }

    override func capabilities() -> [Capability] {
        [.apps, .reviews, .appDetails, .storeListings, .tracks, .appIcons, .releaseManagement, .playUsers]
    }

    override func fetchApps() async throws -> [AppInfo] {
        developer.state.read { $0.apps }
    }

    override func appDetails() -> AppDetails? { FakePlayAppDetails(developer: developer) }
    override func appIcons() -> AppIcons? { FakePlayAppIcons(developer: developer) }
    override func reviews() -> Reviews? { FakePlayReviews(developer: developer) }
    override func storeListings() -> StoreListings? { FakePlayStoreListings(developer: developer) }
    override func tracks() -> Tracks? { FakePlayTracks(developer: developer) }
    override func playUsers() -> PlayUsers? { FakePlayUsers(developer: developer) }
}

// MARK: - App details

final class FakePlayAppDetails: AppDetails, @unchecked Sendable {

    private let developer: FakeGooglePlayDeveloper

    init(developer: FakeGooglePlayDeveloper) {
        self.developer = developer
        super.init(noHandle: .init())
    }

    required init(unsafeFromHandle handle: UInt64) {
        fatalError("Fake capabilities are never lifted from the FFI")
    }

    /// Also the "can this account reach package X?" check of a manual add:
    /// an unknown package is a 404, like Google's answer.
    override func fetchAppDetails(appId: String) async throws -> AppDetailsInfo {
        try developer.state.read { state in
            guard let details = state.details[appId] else { throw FakeCoreError.notFound("Package \(appId)") }
            return details
        }
    }
}

// MARK: - App icons

final class FakePlayAppIcons: AppIcons, @unchecked Sendable {

    private let developer: FakeGooglePlayDeveloper

    init(developer: FakeGooglePlayDeveloper) {
        self.developer = developer
        super.init(noHandle: .init())
    }

    required init(unsafeFromHandle handle: UInt64) {
        fatalError("Fake capabilities are never lifted from the FFI")
    }

    override func fetchIconUrl(appId: String) async throws -> String? {
        developer.state.read { $0.iconUrls[appId] }
    }
}

// MARK: - Store listings

final class FakePlayStoreListings: StoreListings, @unchecked Sendable {

    private let developer: FakeGooglePlayDeveloper

    init(developer: FakeGooglePlayDeveloper) {
        self.developer = developer
        super.init(noHandle: .init())
    }

    required init(unsafeFromHandle handle: UInt64) {
        fatalError("Fake capabilities are never lifted from the FFI")
    }

    override func fetchStoreListings(appId: String) async throws -> [StoreListingInfo] {
        try developer.state.read { state in
            guard let listings = state.listings[appId] else { throw FakeCoreError.notFound("Package \(appId)") }
            return listings
        }
    }
}

// MARK: - Tracks

final class FakePlayTracks: Tracks, @unchecked Sendable {

    private let developer: FakeGooglePlayDeveloper

    init(developer: FakeGooglePlayDeveloper) {
        self.developer = developer
        super.init(noHandle: .init())
    }

    required init(unsafeFromHandle handle: UInt64) {
        fatalError("Fake capabilities are never lifted from the FFI")
    }

    override func fetchTracks(appId: String) async throws -> [TrackInfo] {
        try developer.state.read { state in
            guard let tracks = state.tracks[appId] else { throw FakeCoreError.notFound("Package \(appId)") }
            return tracks
        }
    }

    /// Edit-free `tracks.releases.list`; an unknown track is an empty list.
    override func fetchReleaseSummaries(appId: String, track: String) async throws -> [ReleaseSummaryInfo] {
        try developer.state.read { state in
            guard state.tracks[appId] != nil else { throw FakeCoreError.notFound("Package \(appId)") }
            return state.releaseSummaries(packageName: appId, track: track)
        }
    }

    override func fetchBundles(appId: String) async throws -> [BundleInfo] {
        try developer.state.read { state in
            guard let bundles = state.bundles[appId] else { throw FakeCoreError.notFound("Package \(appId)") }
            return bundles
        }
    }

    /// Applies one typed change to the track, like the core does inside one
    /// edit, and returns the committed track. Validation mirrors the core's
    /// local checks (fraction, priority, version codes → HTTP 400) and a
    /// release that is not on the track any more is `ReleaseNotFound`.
    override func applyReleaseChange(appId: String, track: String, change: ReleaseChange, options: CommitOptions) async throws -> TrackInfo {
        try developer.state.write { state in
            guard var tracks = state.tracks[appId] else { throw FakeCoreError.notFound("Package \(appId)") }
            let index: Int
            if let existing = tracks.firstIndex(where: { $0.track == track }) {
                index = existing
            } else {
                tracks.append(TrackInfo(track: track, releases: []))
                index = tracks.count - 1
            }
            var releases = tracks[index].releases
            var lifecycles = state.lifecycles[appId] ?? [:]
            let newState = options.sendForReview ? FakeGooglePlayState.Lifecycle.inReview : FakeGooglePlayState.Lifecycle.notSentForReview

            func position(of versionCodes: [String]) throws -> Int {
                try FakePlayReleaseRules.validate(versionCodes: versionCodes)
                let wanted = versionCodes.sorted()
                guard let position = releases.firstIndex(where: { $0.versionCodes.sorted() == wanted }) else {
                    throw StackError.ReleaseNotFound(message: "No release with version codes \(wanted.joined(separator: ", ")) on \(track) (fake data).")
                }
                return position
            }
            func markChanged(_ release: TrackReleaseInfo) {
                lifecycles[FakeGooglePlayState.releaseKey(track: track, versionCodes: release.versionCodes)] =
                    release.status == "draft" ? FakeGooglePlayState.Lifecycle.draft : newState
            }

            switch change {
            case .setRollout(let versionCodes, let userFraction):
                try FakePlayReleaseRules.validate(fraction: userFraction)
                let at = try position(of: versionCodes)
                releases[at].status = "inProgress"
                releases[at].userFraction = userFraction
                markChanged(releases[at])
            case .halt(let versionCodes):
                let at = try position(of: versionCodes)
                releases[at].status = "halted"
                markChanged(releases[at])
            case .resume(let versionCodes):
                let at = try position(of: versionCodes)
                releases[at].status = releases[at].userFraction == nil ? "completed" : "inProgress"
                markChanged(releases[at])
            case .complete(let versionCodes):
                let at = try position(of: versionCodes)
                var release = releases[at]
                release.status = "completed"
                release.userFraction = nil
                releases = [release] + releases.enumerated().filter { $0.offset != at && $0.element.status != "completed" }.map(\.element)
                markChanged(release)
            case .updateMetadata(let versionCodes, let update):
                try update.inAppUpdatePriority.map(FakePlayReleaseRules.validate(priority:))
                let at = try position(of: versionCodes)
                if let name = update.name { releases[at].name = name }
                if let notes = update.releaseNotes { releases[at].releaseNotes = notes }
                if let priority = update.inAppUpdatePriority { releases[at].inAppUpdatePriority = priority }
                if let targeting = update.countryTargeting { releases[at].countryTargeting = targeting }
                markChanged(releases[at])
            case .createRelease(let release):
                let created = try FakePlayReleaseRules.release(from: release, bundles: state.bundles[appId] ?? [])
                releases = FakePlayReleaseRules.inserting(created, into: releases)
                markChanged(created)
            case .promote(let fromTrack, let versionCodes, let status, let name, let releaseNotes, let inAppUpdatePriority, let countryTargeting):
                try FakePlayReleaseRules.validate(versionCodes: versionCodes)
                let wanted = versionCodes.sorted()
                guard let source = tracks.first(where: { $0.track == fromTrack })?.releases.first(where: { $0.versionCodes.sorted() == wanted }) else {
                    throw StackError.ReleaseNotFound(message: "No release with version codes \(wanted.joined(separator: ", ")) on \(fromTrack) (fake data).")
                }
                let created = try FakePlayReleaseRules.release(
                    from: NewRelease(
                        versionCodes: source.versionCodes,
                        name: name ?? source.name,
                        releaseNotes: releaseNotes ?? source.releaseNotes,
                        status: status,
                        inAppUpdatePriority: inAppUpdatePriority ?? source.inAppUpdatePriority,
                        countryTargeting: countryTargeting
                    ),
                    bundles: state.bundles[appId] ?? []
                )
                releases = FakePlayReleaseRules.inserting(created, into: releases)
                markChanged(created)
            }

            tracks[index].releases = releases
            state.tracks[appId] = tracks
            state.lifecycles[appId] = lifecycles
            return tracks[index]
        }
    }
}

/// The core's local validation and Play Console's one-pending-release model,
/// for the fake track mutations.
enum FakePlayReleaseRules {

    static func badRequest(_ detail: String) -> StackError {
        .Http(status: 400, message: "\(detail) (fake data).")
    }

    static func validate(fraction: Double) throws {
        guard fraction > 0, fraction < 1 else { throw badRequest("userFraction must be between 0 and 1, exclusive") }
    }

    static func validate(priority: Int32) throws {
        guard (0...5).contains(priority) else { throw badRequest("inAppUpdatePriority must be between 0 and 5") }
    }

    static func validate(versionCodes: [String]) throws {
        guard !versionCodes.isEmpty, versionCodes.allSatisfy({ Int64($0).map { $0 > 0 } ?? false }) else {
            throw badRequest("Version codes must be positive integers")
        }
    }

    /// A track release for `release`; every version code must be an uploaded bundle.
    static func release(from release: NewRelease, bundles: [BundleInfo]) throws -> TrackReleaseInfo {
        try validate(versionCodes: release.versionCodes)
        try release.inAppUpdatePriority.map(validate(priority:))
        let uploaded = Set(bundles.map(\.versionCode))
        if let missing = release.versionCodes.first(where: { !uploaded.contains($0) }) {
            throw badRequest("APK or bundle with version code \(missing) has not been uploaded")
        }
        let status: String
        var fraction: Double?
        switch release.status {
        case .draft: status = "draft"
        case .completed: status = "completed"
        case .inProgress(let userFraction):
            try validate(fraction: userFraction)
            status = "inProgress"
            fraction = userFraction
        }
        return TrackReleaseInfo(
            name: release.name ?? release.versionCodes.joined(separator: ", "),
            status: status,
            versionCodes: release.versionCodes,
            userFraction: fraction,
            releaseNotes: release.releaseNotes,
            inAppUpdatePriority: release.inAppUpdatePriority,
            countryTargeting: release.countryTargeting
        )
    }

    /// Draft replaces drafts; in progress replaces drafts and rollouts;
    /// completed replaces everything. The new release goes first.
    static func inserting(_ release: TrackReleaseInfo, into releases: [TrackReleaseInfo]) -> [TrackReleaseInfo] {
        let replaced: Set<String>
        switch release.status {
        case "draft": replaced = ["draft"]
        case "inProgress": replaced = ["draft", "inProgress", "halted"]
        default: return [release]
        }
        return [release] + releases.filter { !replaced.contains($0.status ?? "") }
    }
}

// MARK: - Users

/// The developer account's users. The developer id must be numeric, like
/// Google's (anything else is a 404); every write lands in the shared state.
final class FakePlayUsers: PlayUsers, @unchecked Sendable {

    private let developer: FakeGooglePlayDeveloper

    init(developer: FakeGooglePlayDeveloper) {
        self.developer = developer
        super.init(noHandle: .init())
    }

    required init(unsafeFromHandle handle: UInt64) {
        fatalError("Fake capabilities are never lifted from the FFI")
    }

    private func validate(developerId: String) throws {
        guard !developerId.isEmpty, developerId.allSatisfy(\.isNumber) else {
            throw FakeCoreError.notFound("Developer account \(developerId)")
        }
    }

    private func resourceName(developerId: String, email: String) -> String {
        "developers/\(developerId)/users/\(email)"
    }

    override func fetchUsers(developerId: String) async throws -> [PlayUserInfo] {
        try validate(developerId: developerId)
        return developer.state.read { state in
            state.users.map { user in
                var user = user
                user.name = resourceName(developerId: developerId, email: user.email)
                return user
            }
        }
    }

    override func inviteUser(developerId: String, email: String, accountPermissions: [String], grants: [PlayGrantInfo], expirationTime: String?) async throws -> PlayUserInfo {
        try validate(developerId: developerId)
        let user = PlayUserInfo(
            email: email, name: resourceName(developerId: developerId, email: email), accessState: "INVITED",
            expirationTime: expirationTime, developerAccountPermissions: accountPermissions, grants: grants, partial: false
        )
        try developer.state.write { state in
            guard !state.users.contains(where: { $0.email.caseInsensitiveCompare(email) == .orderedSame }) else {
                throw StackError.Http(status: 409, message: "User \(email) already exists (fake data).")
            }
            state.users.append(user)
        }
        return user
    }

    override func updateUser(developerId: String, email: String, accountPermissions: [String], expirationTime: String?) async throws -> PlayUserInfo {
        try validate(developerId: developerId)
        return try modify(email: email) { user in
            user.developerAccountPermissions = accountPermissions
            user.expirationTime = expirationTime
        }
    }

    override func deleteUser(developerId: String, email: String) async throws {
        try validate(developerId: developerId)
        try developer.state.write { state in
            guard let index = state.users.firstIndex(where: { $0.email == email }) else { throw FakeCoreError.notFound("User \(email)") }
            state.users.remove(at: index)
        }
    }

    override func setGrant(developerId: String, email: String, packageName: String, appLevelPermissions: [String]) async throws -> PlayGrantInfo {
        try validate(developerId: developerId)
        let grant = PlayGrantInfo(packageName: packageName, appLevelPermissions: appLevelPermissions)
        _ = try modify(email: email) { user in
            user.grants.removeAll { $0.packageName == packageName }
            user.grants.append(grant)
        }
        return grant
    }

    override func deleteGrant(developerId: String, email: String, packageName: String) async throws {
        try validate(developerId: developerId)
        _ = try modify(email: email) { user in
            user.grants.removeAll { $0.packageName == packageName }
        }
    }

    private func modify(email: String, _ change: (inout PlayUserInfo) -> Void) throws -> PlayUserInfo {
        try developer.state.write { state in
            guard let index = state.users.firstIndex(where: { $0.email == email }) else { throw FakeCoreError.notFound("User \(email)") }
            change(&state.users[index])
            return state.users[index]
        }
    }
}

// MARK: - Reviews

final class FakePlayReviews: Reviews, @unchecked Sendable {

    private let developer: FakeGooglePlayDeveloper

    init(developer: FakeGooglePlayDeveloper) {
        self.developer = developer
        super.init(noHandle: .init())
    }

    required init(unsafeFromHandle handle: UInt64) {
        fatalError("Fake capabilities are never lifted from the FFI")
    }

    override func fetchCustomerReviews(appId: String) async throws -> [CustomerReview] {
        developer.state.read { FakeReviewPaging.sorted($0.reviews[appId] ?? [], by: "-createdDate") }
    }

    /// Google serves newest first only; the core rejects any other sort.
    override func fetchCustomerReviewsPage(appId: String, sort: String, filterRating: [String], limit: UInt32, pageToken: String?) async throws -> CustomerReviewsPage {
        guard sort == "-createdDate" else { throw FakeCoreError.unsupported("Sorting Google Play reviews by \(sort)") }
        let ratings = Set(filterRating.compactMap(Int32.init))
        let all = developer.state.read { state in
            FakeReviewPaging.sorted(state.reviews[appId] ?? [], by: sort).filter { ratings.isEmpty || ratings.contains($0.rating) }
        }
        return FakeReviewPaging.page(all, limit: limit, pageToken: pageToken)
    }

    /// An upsert: replying again replaces the previous reply. Google rejects
    /// replies over 350 characters with an HTTP 400.
    override func replyToReview(reviewId: String, body: String) async throws -> ReviewResponse {
        guard body.count <= 350 else {
            throw StackError.Http(status: 400, message: "Reply text is too long (fake data).")
        }
        let response = ReviewResponse(id: "\(reviewId)/reply", body: body, state: nil, lastModifiedDate: FakeClock.iso(Date()))
        try developer.state.write { state in
            guard let packageName = state.packageName(forReview: reviewId),
                  let index = state.reviews[packageName]?.firstIndex(where: { $0.id == reviewId }) else {
                throw FakeCoreError.notFound("Review \(reviewId)")
            }
            state.reviews[packageName]![index].response = response
        }
        return response
    }

    override func deleteReviewResponse(responseId: String) async throws {
        throw FakeCoreError.unsupported("Deleting a Google Play reply")
    }

    override func fetchReviewSubmissions(appId: String) async throws -> [ReviewSubmission] {
        throw FakeCoreError.unsupported("Review submissions")
    }

    override func submitReviewSubmission(submissionId: String) async throws {
        throw FakeCoreError.unsupported("Review submissions")
    }

    override func discardReviewSubmission(submissionId: String) async throws {
        throw FakeCoreError.unsupported("Review submissions")
    }
}
#endif
