import Foundation
import SwiftData
import StackCore

/// Read-only snapshot of the shared store, sliced per widget.
struct WidgetSnapshot: Sendable {
    var inReview: [WidgetApp] = []
    var awaitingRelease: [WidgetApp] = []
    var phasedByAppId: [String: WidgetPhasedRelease] = [:]
    var recentReviews: [WidgetReviewItem] = []

    static let empty = WidgetSnapshot()
}

/// Loads widget data from the shared App Group SwiftData store. Read-only:
/// the widget never hits the network or Keychain. The app keeps the store fresh
/// via its background sync and reloads timelines afterwards.
enum WidgetDataLoader {

    private static let recentReviewsLimit = 5

    static func load() async -> WidgetSnapshot {
        guard let storage = makeStorage() else { return .empty }

        do {
            let apps = try await storage.fetchAll(WidgetApp.self, typeName: "AppModel")
            let active = apps.filter { $0.isArchived != true }

            // Phased releases are stored under identifier "phased.{appId}".
            var phasedByAppId: [String: WidgetPhasedRelease] = [:]
            for app in active {
                if let phased = try? await storage.fetch(
                    WidgetPhasedRelease.self,
                    id: "phased.\(app.id)",
                    typeName: "PhasedReleaseModel"
                ) {
                    phasedByAppId[app.id] = phased
                }
            }

            let (inReview, awaiting) = categorize(active, phasedByAppId: phasedByAppId)

            let reviews = try await storage.fetchAll(WidgetReview.self, typeName: "CustomerReviewModel")
            // Match reviews only against active (non-archived) apps so reviews
            // from archived apps never appear in the Recent Reviews widget.
            let appById = Dictionary(uniqueKeysWithValues: active.map { ($0.id, $0) })
            let recent = reviews
                .compactMap { review -> WidgetReviewItem? in
                    guard let appId = review.appId, let app = appById[appId] else { return nil }
                    return WidgetReviewItem(review: review, app: withIcon(app))
                }
                .sorted { ($0.review.createdDate ?? .distantPast) > ($1.review.createdDate ?? .distantPast) }
                .prefix(recentReviewsLimit)
                .map { $0 }

            return WidgetSnapshot(
                inReview: inReview.sorted(by: sortByRecency).map(withIcon),
                awaitingRelease: awaiting.sorted(by: sortByRecency).map(withIcon),
                phasedByAppId: phasedByAppId,
                recentReviews: recent
            )
        } catch {
            Log.print.error("[WidgetExtension] Failed to load snapshot: \(error.localizedDescription)")
            return .empty
        }
    }

    // MARK: - Helpers

    /// Attaches cached icon bytes (from the shared App Group container) to an app.
    private static func withIcon(_ app: WidgetApp) -> WidgetApp {
        var copy = app
        copy.iconData = WidgetIconCache.iconData(forIconURL: app.iconUrl)
        return copy
    }

    private static func makeStorage() -> SwiftDataStorable? {
        do {
            let configuration = ModelConfiguration(
                groupContainer: .identifier(AppGroup.identifier)
            )
            let container = try ModelContainer(for: PersistedItem.self, configurations: configuration)
            return SwiftDataStorable.make(modelContainer: container)
        } catch {
            Log.print.error("[WidgetExtension] Failed to open shared store: \(error.localizedDescription)")
            return nil
        }
    }

    private static func categorize(
        _ apps: [WidgetApp],
        phasedByAppId: [String: WidgetPhasedRelease]
    ) -> (inReview: [WidgetApp], awaitingRelease: [WidgetApp]) {
        var inReview: [WidgetApp] = []
        var awaiting: [WidgetApp] = []
        for app in apps {
            // In Review is expanded per platform: an app with an iOS version in
            // review and a tvOS version with an invalid binary yields two rows.
            if let platformVersions = app.platformVersions, !platformVersions.isEmpty {
                for version in platformVersions where WidgetAppStatus.isInReview(version.appStoreState) {
                    var entry = app
                    entry.appStoreState = version.appStoreState
                    entry.platform = version.platform
                    entry.versionString = version.versionString
                    inReview.append(entry)
                }
            } else if WidgetAppStatus.isInReview(app.appStoreState) {
                inReview.append(app)
            }

            // Awaiting Release stays on the app's primary (most-recent) state.
            let state = app.appStoreState
            if state == "PENDING_DEVELOPER_RELEASE" {
                awaiting.append(app)
            } else if state == "READY_FOR_SALE",
                      let phased = phasedByAppId[app.id],
                      phased.state == "ACTIVE" || phased.state == "PAUSED" {
                awaiting.append(app)
            }
        }
        return (inReview, awaiting)
    }

    private static func sortByRecency(_ a: WidgetApp, _ b: WidgetApp) -> Bool {
        switch (a.lastModifiedDate, b.lastModifiedDate) {
        case let (dateA?, dateB?): return dateA > dateB
        case (_?, nil):            return true
        case (nil, _?):            return false
        case (nil, nil):           return a.name < b.name
        }
    }
}
