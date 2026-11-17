import Foundation

/// What the WidgetKit extension draws (plan H6): the three Home lists, already
/// categorized by the app for both stores. The app writes it after each sync
/// and after a dashboard-affecting write; the extension only reads it, so the
/// in-app and home-screen widgets can never disagree again.
public struct WidgetDashboardSnapshot: Codable, Equatable, Sendable {
    /// Bumped when the format changes incompatibly; an older file is ignored.
    public static let currentVersion = 1

    public var version: Int
    public var generatedAt: Date
    /// First rows of each list (capped by the writer) and the full counts.
    public var inReview: [WidgetDashboardRow]
    public var inReviewCount: Int
    public var awaitingRelease: [WidgetDashboardRow]
    public var awaitingReleaseCount: Int
    public var recentReviews: [WidgetDashboardReview]

    public init(
        generatedAt: Date,
        inReview: [WidgetDashboardRow],
        inReviewCount: Int? = nil,
        awaitingRelease: [WidgetDashboardRow],
        awaitingReleaseCount: Int? = nil,
        recentReviews: [WidgetDashboardReview]
    ) {
        self.version = Self.currentVersion
        self.generatedAt = generatedAt
        self.inReview = inReview
        self.inReviewCount = inReviewCount ?? inReview.count
        self.awaitingRelease = awaitingRelease
        self.awaitingReleaseCount = awaitingReleaseCount ?? awaitingRelease.count
        self.recentReviews = recentReviews
    }

    public static let empty = WidgetDashboardSnapshot(generatedAt: .distantPast, inReview: [], awaitingRelease: [], recentReviews: [])

    /// Platforms the reviews come from (the Recent Reviews header glyphs).
    public var reviewPlatforms: [DashboardPlatform] {
        let platforms = Set(recentReviews.compactMap(\.platform).map { $0 == .android ? DashboardPlatform.android : .iOS })
        return platforms.sorted { $0.sortRank < $1.sortRank }
    }
}

/// One ready-to-draw In Review / Awaiting Release row.
public struct WidgetDashboardRow: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var iconUrl: String?
    public var platform: DashboardPlatform?
    /// Already localized by the app ("Waiting for Review", "Production · In review").
    public var statusText: String
    public var statusColor: DashboardStatusColor
    public var versionText: String?
    public var progress: DashboardProgress?
    /// `stackconnect://app/{accountId}/{appId}`.
    public var deepLink: String?

    public init(
        id: String, name: String, iconUrl: String?, platform: DashboardPlatform?, statusText: String,
        statusColor: DashboardStatusColor, versionText: String?, progress: DashboardProgress?, deepLink: String?
    ) {
        self.id = id
        self.name = name
        self.iconUrl = iconUrl
        self.platform = platform
        self.statusText = statusText
        self.statusColor = statusColor
        self.versionText = versionText
        self.progress = progress
        self.deepLink = deepLink
    }
}

/// One ready-to-draw Recent Reviews row.
public struct WidgetDashboardReview: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var appName: String
    public var iconUrl: String?
    public var platform: DashboardPlatform?
    public var rating: Int
    public var title: String?
    public var body: String?
    public var createdDate: Date?
    public var hasResponse: Bool
    /// `stackconnect://review/{accountId}/{appId}/{reviewId}`.
    public var deepLink: String?

    public init(
        id: String, appName: String, iconUrl: String?, platform: DashboardPlatform?, rating: Int, title: String?,
        body: String?, createdDate: Date?, hasResponse: Bool, deepLink: String?
    ) {
        self.id = id
        self.appName = appName
        self.iconUrl = iconUrl
        self.platform = platform
        self.rating = rating
        self.title = title
        self.body = body
        self.createdDate = createdDate
        self.hasResponse = hasResponse
        self.deepLink = deepLink
    }
}

/// The snapshot file, `WidgetDashboard.json` in the App Group container (next
/// to the widget icon cache). A plain file rather than a SwiftData record: the
/// extension needs no model container, and the DEBUG fake data mode can move it
/// out of the App Group exactly like the icon cache.
public enum WidgetDashboardSnapshotStore {

    public static let fileName = "WidgetDashboard.json"

    /// Replaces the App Group location (set once at launch). The DEBUG fake
    /// data mode points it at a private folder unless it was asked to feed the
    /// home-screen widgets (`-StackFakeDataWidgets YES`).
    nonisolated(unsafe) public static var directoryOverride: URL?

    public static func fileURL() -> URL? {
        if let directoryOverride {
            try? FileManager.default.createDirectory(at: directoryOverride, withIntermediateDirectories: true)
            return directoryOverride.appendingPathComponent(fileName)
        }
        return FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: AppGroup.identifier)?
            .appendingPathComponent(fileName)
    }

    public static func save(_ snapshot: WidgetDashboardSnapshot, to url: URL? = fileURL()) throws {
        guard let url else { throw CocoaError(.fileNoSuchFile) }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        try encoder.encode(snapshot).write(to: url, options: .atomic)
    }

    /// `nil` when there is no snapshot yet or it can't be read (another format).
    public static func load(from url: URL? = fileURL()) -> WidgetDashboardSnapshot? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        guard let snapshot = try? decoder.decode(WidgetDashboardSnapshot.self, from: data),
              snapshot.version == WidgetDashboardSnapshot.currentVersion else { return nil }
        return snapshot
    }
}
