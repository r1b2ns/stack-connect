import SwiftUI

/// Review / publishing state of a Google Play release, from the edit-free
/// `tracks.releases.list` (`releaseLifecycleState`). Unknown values (a state
/// Google adds later, or none at all) are kept as `.unknown` with their raw
/// value, so decoding never fails and the raw value survives a cache round trip.
enum GooglePlayReleaseLifecycleState: Hashable, Sendable {
    case draft
    case notSentForReview
    case inReview
    case approvedNotPublished
    case notApproved
    case published
    case unknown(String?)

    private static let prefix = "RELEASE_LIFECYCLE_STATE_"

    init(raw: String?) {
        switch raw {
        case Self.prefix + "DRAFT":                  self = .draft
        case Self.prefix + "NOT_SENT_FOR_REVIEW":    self = .notSentForReview
        case Self.prefix + "IN_REVIEW":              self = .inReview
        case Self.prefix + "APPROVED_NOT_PUBLISHED": self = .approvedNotPublished
        case Self.prefix + "NOT_APPROVED":           self = .notApproved
        case Self.prefix + "PUBLISHED":              self = .published
        default:                                     self = .unknown(raw)
        }
    }

    /// The raw Google value (`RELEASE_LIFECYCLE_STATE_*`).
    var rawValue: String? {
        switch self {
        case .draft:                return Self.prefix + "DRAFT"
        case .notSentForReview:     return Self.prefix + "NOT_SENT_FOR_REVIEW"
        case .inReview:             return Self.prefix + "IN_REVIEW"
        case .approvedNotPublished: return Self.prefix + "APPROVED_NOT_PUBLISHED"
        case .notApproved:          return Self.prefix + "NOT_APPROVED"
        case .published:            return Self.prefix + "PUBLISHED"
        case .unknown(let raw):     return raw
        }
    }

    var displayName: String {
        switch self {
        case .draft:                return String(localized: "Draft")
        case .notSentForReview:     return String(localized: "Not sent for review")
        case .inReview:             return String(localized: "In review")
        case .approvedNotPublished: return String(localized: "Approved, not published")
        case .notApproved:          return String(localized: "Not approved")
        case .published:            return String(localized: "Published")
        case .unknown:              return String(localized: "Unknown")
        }
    }

    /// Dot color: draft and not sent gray, in review orange, approved yellow,
    /// not approved red, published green.
    var color: Color {
        switch self {
        case .draft, .notSentForReview: return .gray
        case .inReview:                 return .orange
        case .approvedNotPublished:     return .yellow
        case .notApproved:              return .red
        case .published:                return .green
        case .unknown:                  return .secondary
        }
    }

    /// Which release a track's status line shows when it has several: the one
    /// that needs attention first. Lower is more relevant.
    var attentionRank: Int {
        switch self {
        case .notApproved:          return 0
        case .inReview:             return 1
        case .approvedNotPublished: return 2
        case .notSentForReview:     return 3
        case .draft:                return 4
        case .published:            return 5
        case .unknown:              return 6
        }
    }
}

extension GooglePlayReleaseLifecycleState: Codable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(raw: container.decodeNil() ? nil : try container.decode(String.self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let rawValue {
            try container.encode(rawValue)
        } else {
            try container.encodeNil()
        }
    }
}

/// One release of a track as `tracks.releases.list` reports it (no edit, plan
/// R1): its review / publishing state, not its rollout. Obsolete releases are
/// not listed by Google.
struct GooglePlayReleaseSummaryModel: Codable, Hashable, Sendable {
    /// Raw track name (`production`, `beta`, `alpha`, `internal` or custom).
    let track: String
    var name: String?
    var lifecycleState: GooglePlayReleaseLifecycleState
    /// Version codes as decimal strings.
    var versionCodes: [String]

    var trackKind: GooglePlayTrackKind {
        GooglePlayTrackKind(track: track)
    }

    /// A release is identified by its track and sorted version codes (plan R7).
    var releaseKey: GooglePlayReleaseKey {
        GooglePlayReleaseKey(track: track, versionCodes: versionCodes)
    }

    /// The release name without a trailing " (versionCode)" Play Console adds
    /// (e.g. "4.2.0 (4210)" → "4.2.0"); falls back to the version codes.
    var shortName: String {
        GooglePlayReleaseNaming.shortName(name: name, versionCodes: versionCodes)
    }

    /// The highest version code, for ordering releases newest first.
    var highestVersionCode: Int64 {
        versionCodes.compactMap(Int64.init).max() ?? 0
    }

    /// The release a track's one-line status shows: the one that needs
    /// attention first (`attentionRank`), then the newest.
    static func headline(of summaries: [GooglePlayReleaseSummaryModel]) -> GooglePlayReleaseSummaryModel? {
        summaries.min { lhs, rhs in
            if lhs.lifecycleState.attentionRank != rhs.lifecycleState.attentionRank {
                return lhs.lifecycleState.attentionRank < rhs.lifecycleState.attentionRank
            }
            return lhs.highestVersionCode > rhs.highestVersionCode
        }
    }
}

/// Identity of a release across `releases.list` and `edits.tracks` (plan R7):
/// track + sorted version codes. Names are editable and indexes change when
/// Google drops obsolete releases.
struct GooglePlayReleaseKey: Hashable, Sendable {
    let track: String
    let versionCodes: [String]

    init(track: String, versionCodes: [String]) {
        self.track = track
        self.versionCodes = versionCodes.sorted()
    }
}

/// Display names of releases shared by summaries and track releases.
enum GooglePlayReleaseNaming {

    static func shortName(name: String?, versionCodes: [String]) -> String {
        guard let trimmed = name?.trimmingCharacters(in: .whitespaces), !trimmed.isEmpty else {
            return versionCodes.isEmpty ? String(localized: "Untitled release") : versionCodes.joined(separator: ", ")
        }
        for code in versionCodes {
            let suffix = " (\(code))"
            if trimmed.hasSuffix(suffix), trimmed.count > suffix.count {
                return String(trimmed.dropLast(suffix.count))
            }
        }
        return trimmed
    }
}

// MARK: - Cache

/// Cached release summaries of one app, every track it was asked for
/// (`googleplay-releases.{accountId}.{packageName}`). Written by the app list
/// after each sync; edit-free, so it may refresh automatically (plan R1).
struct GooglePlayReleaseSummariesCache: GooglePlayAppScopedCache {
    static let keyPrefix = "googleplay-releases"
    let accountId: String
    let packageName: String
    var summaries: [GooglePlayReleaseSummaryModel]
    var fetchedAt: Date?

    /// Summaries grouped per track, in display order (production → testing →
    /// custom), tracks without a release left out.
    var tracks: [(track: String, releases: [GooglePlayReleaseSummaryModel])] {
        let grouped = Dictionary(grouping: summaries, by: \.track)
        let ordered = GooglePlayTrackModel.sorted(grouped.keys.map { GooglePlayTrackModel(track: $0, releases: []) })
        return ordered.compactMap { track in
            guard let releases = grouped[track.track], !releases.isEmpty else { return nil }
            return (track.track, releases.sorted { $0.highestVersionCode > $1.highestVersionCode })
        }
    }
}
