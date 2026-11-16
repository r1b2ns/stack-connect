import SwiftUI

// MARK: - Shared Data Loading

enum HomeWidgetDataLoader {

    static func loadAccounts(storage: PersistentStorable) async -> [String: AccountModel] {
        do {
            let accounts: [AccountModel] = try await storage.fetchAll(AccountModel.self)
            var map: [String: AccountModel] = [:]
            for var account in accounts {
                account.fillMissingRules()
                map[account.id] = account
            }
            return map
        } catch {
            Log.print.error("[Widget] Failed to load accounts: \(error.localizedDescription)")
            return [:]
        }
    }

    /// Drops apps whose `accountId` matches no known account.
    ///
    /// Home widgets are the only place that reads apps across *all* accounts
    /// (`fetchAll(AppModel.self)`); the rest of the app scopes every list by the
    /// selected account. An app left behind by an account that went away — each
    /// import mints a fresh account id, so a re-import orphans the old records —
    /// is therefore invisible everywhere except here, where it would still be
    /// listed and counted.
    ///
    /// Guard: an empty `accountsMap` means either the fetch failed or the install
    /// genuinely has no accounts. Neither is a mandate to hide anything, so
    /// nothing is filtered — a transient storage failure must never blank out the
    /// whole Home. Filtering only happens against a non-empty account list.
    static func filterKnownAccounts(
        _ apps: [AppModel],
        accountsMap: [String: AccountModel]
    ) -> [AppModel] {
        guard !accountsMap.isEmpty else { return apps }
        return apps.filter { accountsMap[$0.accountId] != nil }
    }

    /// Loads phased releases keyed by version id (matching the
    /// `"phased.{versionId}"` storage scheme written by `SyncService.syncPhased`).
    /// Looks up every version id in `awaitingVersions` (a still-phasing
    /// `readyForSale` version kept behind a newer prepared one) AND
    /// `platformVersions` (latest per platform), plus the app id as a fallback for
    /// single-platform apps that predate per-version ids.
    static func loadPhasedReleases(
        for apps: [AppModel],
        storage: PersistentStorable
    ) async -> [String: PhasedReleaseModel] {
        // Build the deduplicated set of keys to look up.
        var keys = Set<String>()
        for app in apps {
            let versionIds = ((app.awaitingVersions ?? []) + (app.platformVersions ?? []))
                .compactMap { $0.id }
            if versionIds.isEmpty {
                keys.insert(app.id)
            } else {
                keys.formUnion(versionIds)
            }
        }

        var result: [String: PhasedReleaseModel] = [:]
        for key in keys {
            if let phased: PhasedReleaseModel = try? await storage.fetch(PhasedReleaseModel.self, id: "phased.\(key)") {
                result[key] = phased
            }
        }
        return result
    }

    /// Resolves the phased release for a single awaiting-release entry from a
    /// version-id-keyed map. An expanded entry keeps the app's full
    /// `awaitingVersions`, and its own `platform`/`versionString` identify which
    /// one it represents — so an app exposing two versions for one platform (a
    /// still-phasing `readyForSale` one behind a newer prepared one) resolves each
    /// to its own phased release. Falls back to the latest-per-platform
    /// `platformVersions` (legacy data), then the app id (single-platform apps).
    static func phasedRelease(
        for entry: AppModel,
        in phasedByVersionId: [String: PhasedReleaseModel]
    ) -> PhasedReleaseModel? {
        if let awaitingVersions = entry.awaitingVersions {
            let versionId = awaitingVersions.first {
                $0.platform == entry.platform && $0.versionString == entry.versionString
            }?.id
            return versionId.flatMap { phasedByVersionId[$0] }
        }
        if let platformVersions = entry.platformVersions, !platformVersions.isEmpty {
            let versionId = platformVersions.first { $0.platform == entry.platform }?.id
            return versionId.flatMap { phasedByVersionId[$0] }
        }
        return phasedByVersionId[entry.id]
    }

    /// The Google Play apps the dashboard may show: every app cached for a
    /// known Play account allowed to `resource` (`.version` for the status
    /// widgets, `.review` for reviews), inside the account's per-app scope.
    /// With `includesReleaseCaches` each app also carries its release
    /// summaries and tracks caches. Never opens an edit nor hits the network.
    static func loadGooglePlaySources(
        storage: PersistentStorable,
        accounts: [String: AccountModel],
        requiring resource: AccountRuleResource,
        includesReleaseCaches: Bool
    ) async -> [GooglePlayDashboardSource] {
        let playAccounts = accounts.values
            .filter { $0.providerType == .googlePlay && $0.canView(resource) }
            .sorted { $0.createdAt < $1.createdAt }
        var sources: [GooglePlayDashboardSource] = []
        for account in playAccounts {
            let apps = ((try? await storage.fetch([GooglePlayAppItem].self, id: GooglePlayAppItem.cacheKey(accountId: account.id))) ?? nil) ?? []
            for app in apps where account.allowsApp(bundleId: app.packageName) {
                var summaries: GooglePlayReleaseSummariesCache?
                var tracks: GooglePlayTracksCache?
                if includesReleaseCaches {
                    summaries = await GooglePlayAppCacheStore<GooglePlayReleaseSummariesCache>(
                        storage: storage, accountId: account.id, packageName: app.packageName
                    ).load()
                    tracks = await GooglePlayAppCacheStore<GooglePlayTracksCache>(
                        storage: storage, accountId: account.id, packageName: app.packageName
                    ).load()
                }
                sources.append(GooglePlayDashboardSource(account: account, app: app, summaries: summaries, tracks: tracks))
            }
        }
        return sources
    }

    static func sortByRecency(_ a: AppModel, _ b: AppModel) -> Bool {
        switch (a.lastModifiedDate, b.lastModifiedDate) {
        case let (dateA?, dateB?): return dateA > dateB
        case (_?, nil):            return true
        case (nil, _?):            return false
        case (nil, nil):           return a.name < b.name
        }
    }

}

// MARK: - Header

struct HomeWidgetSectionHeader: View {
    let icon: String
    let title: String
    let count: Int
    var tint: Color = .primary

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.headline)
                .foregroundStyle(tint)
            Text(title)
                .font(.headline)
                .fontWeight(.semibold)
            if count > 0 {
                Text("(\(count))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}

// MARK: - Empty Row

struct HomeWidgetEmptyRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(.tertiary)
            Text(text)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Footnote

/// A secondary note at the bottom of a widget card (prototype `.sf`).
struct HomeWidgetFootnote: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 2)
    }
}

// MARK: - App Row

/// One In Review / Awaiting Release row: icon, name (with the platform glyph
/// when the list shows no platform headers), status line and, for an awaiting
/// release, its phased-release or staged-rollout progress.
struct HomeAppRowView: View {
    let entry: DashboardEntry
    var showsPlatform: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            HomeAppIconView(url: entry.iconURL)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(entry.name)
                        .font(.body)
                        .fontWeight(.medium)
                        .lineLimit(1)

                    if showsPlatform, let platform = entry.platform {
                        StackPlatformGlyphView(platform: platform)
                    }
                }

                StackStatusLine(color: entry.statusColor.color, text: entry.statusText, detail: entry.versionText, wraps: true)

                if let progress = entry.progress {
                    HomeDashboardProgressView(progress: progress)
                        .padding(.top, 4)
                }
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }
}

/// Rows grouped by platform (App Store platforms, then Android) with a glyph
/// header per group when there is more than one. Shared by the In Review and
/// Awaiting Release widgets.
struct HomeDashboardEntryList: View {
    let entries: [DashboardEntry]
    let onSelect: (DashboardEntry) -> Void

    var body: some View {
        let groups = DashboardEntryBuilder.groupByPlatform(entries)
        let showsHeaders = groups.count > 1
        ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
            if showsHeaders, let platform = group.platform {
                StackPlatformLabel(platform: platform)
                    .padding(.top, 4)
            }
            ForEach(group.entries) { entry in
                StackTrackedButton(.widgetApp, on: .home) {
                    onSelect(entry)
                } label: {
                    HomeAppRowView(entry: entry, showsPlatform: !showsHeaders)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.primary)
            }
        }
    }
}

struct HomeAppIconView: View {
    let url: URL?
    var size: CGFloat = 44

    private var cornerRadius: CGFloat { size * 0.227 }

    var body: some View {
        // The gray placeholder also stands in while the icon downloads (no spinner).
        StackAppIcon(url: url, size: size, cornerRadius: cornerRadius) {
            placeholder
        } loading: {
            placeholder
        }
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(Color.gray.opacity(0.15))
            .overlay(
                Image(systemName: "app.fill")
                    .font(.system(size: size * 0.4))
                    .foregroundStyle(.gray.opacity(0.4))
            )
    }
}

// MARK: - Progress

/// The bar under an Awaiting Release row: App Store phased release ("Day 3 of
/// 7", orange when paused) or Google Play staged rollout (the percentage is in
/// the status line; the caption dates the last value read, plan H3).
struct HomeDashboardProgressView: View {
    let progress: DashboardProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ProgressView(value: progress.value)
                .tint(progress.isPaused ? .orange : .blue)
            switch progress {
            case let .phased(day, total, paused):
                HStack(spacing: 6) {
                    if paused {
                        Image(systemName: "pause.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                        Text(String(localized: "Paused"))
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundStyle(.orange)
                        Text(verbatim: "·")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    Text(String(localized: "Day \(day) of \(total)"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            case let .rollout(_, _, asOf):
                if let asOf {
                    Text(String(
                        localized: "Rollout as of \(asOf.formatted(.dateTime.month(.abbreviated).day()))",
                        comment: "Caption under a Google Play staged rollout bar on the Home: when the percentage was last read."
                    ))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - Review Row

/// One review: app icon, name and platform glyph with the date, stars, title,
/// body and a "Replied" caption. Used by Recent Reviews and All Reviews (where
/// the app is in the section header, `showsApp: false`).
struct HomeReviewRowView: View {
    let item: DashboardReview
    var showsApp: Bool = true

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if showsApp {
                HomeAppIconView(url: item.iconURL, size: 24)
                    .padding(.top, 2)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    if showsApp {
                        Text(item.appName)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .lineLimit(1)
                        if let platform = item.platform {
                            StackPlatformGlyphView(platform: platform)
                        }
                    } else {
                        HomeStarsView(rating: item.review.rating)
                    }

                    Spacer(minLength: 0)

                    if let date = item.review.createdDate {
                        // "2 hr. ago", "yesterday" (prototype: "2h ago").
                        Text(date, format: .relative(presentation: .named, unitsStyle: .abbreviated))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }

                if showsApp {
                    HomeStarsView(rating: item.review.rating)
                }

                if let title = item.review.title, !title.isEmpty {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                }
                if let body = item.review.body, !body.isEmpty {
                    Text(body)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                if item.review.hasResponse {
                    HomeReviewAnsweredBadge()
                }
            }

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.top, 2)
        }
        .padding(.vertical, 2)
    }
}

struct HomeReviewAnsweredBadge: View {
    var body: some View {
        Label(String(localized: "Replied"), systemImage: "checkmark.bubble.fill")
            .font(.caption2)
            .fontWeight(.medium)
            .foregroundStyle(.green)
            .labelStyle(.titleAndIcon)
    }
}

struct HomeStarsView: View {
    let rating: Int

    var body: some View {
        HStack(spacing: 1) {
            ForEach(0..<5, id: \.self) { index in
                Image(systemName: index < rating ? "star.fill" : "star")
                    .font(.caption2)
                    .foregroundStyle(.yellow)
            }
        }
    }
}

// MARK: - Color Mapping

extension AppStoreStateColor {
    var swiftUIColor: Color {
        switch self {
        case .green:  return .green
        case .orange: return .orange
        case .red:    return .red
        case .gray:   return .gray
        case .blue:   return .blue
        case .yellow: return .yellow
        }
    }
}
