import SwiftUI

/// A Google Play release track with its releases (Android Publisher
/// `edits.tracks`). Read-only. Tracks without a release are kept with an empty
/// `releases`.
struct GooglePlayTrackModel: Codable, Hashable, Identifiable {
    /// Raw track name: `production`, `beta`, `alpha`, `internal` or a custom
    /// closed-testing track name.
    let track: String
    var releases: [GooglePlayReleaseModel]

    var id: String { track }

    var kind: GooglePlayTrackKind {
        GooglePlayTrackKind(track: track)
    }

    /// Display order: production, open, closed and internal testing, then
    /// custom tracks by name.
    static func sorted(_ tracks: [GooglePlayTrackModel]) -> [GooglePlayTrackModel] {
        tracks.sorted { lhs, rhs in
            if lhs.kind.sortRank != rhs.kind.sortRank {
                return lhs.kind.sortRank < rhs.kind.sortRank
            }
            return lhs.track.localizedCaseInsensitiveCompare(rhs.track) == .orderedAscending
        }
    }
}

/// The well-known Play tracks, named as Play Console shows them.
enum GooglePlayTrackKind: Hashable {
    case production
    /// `beta`
    case openTesting
    /// `alpha`
    case closedTesting
    /// `internal`
    case internalTesting
    /// Any other (closed testing) track, by its raw name.
    case custom(String)

    init(track: String) {
        switch track.lowercased() {
        case "production": self = .production
        case "beta":       self = .openTesting
        case "alpha":      self = .closedTesting
        case "internal":   self = .internalTesting
        default:           self = .custom(track)
        }
    }

    var displayName: String {
        switch self {
        case .production:      return String(localized: "Production")
        case .openTesting:     return String(localized: "Open testing")
        case .closedTesting:   return String(localized: "Closed testing")
        case .internalTesting: return String(localized: "Internal testing")
        case .custom(let name): return name
        }
    }

    var icon: String {
        switch self {
        case .production:      return "globe"
        case .openTesting:     return "person.3.fill"
        case .closedTesting:   return "lock.fill"
        case .internalTesting: return "hammer.fill"
        case .custom:          return "tag.fill"
        }
    }

    fileprivate var sortRank: Int {
        switch self {
        case .production:      return 0
        case .openTesting:     return 1
        case .closedTesting:   return 2
        case .internalTesting: return 3
        case .custom:          return 4
        }
    }
}

/// One release on a Google Play track.
struct GooglePlayReleaseModel: Codable, Hashable {
    /// Release name as set in Play Console (often the version name).
    var name: String?
    var status: GooglePlayReleaseStatus
    /// Version codes as decimal strings (Play's int64 values).
    var versionCodes: [String]
    /// Staged-rollout fraction in `(0, 1)`, set only while a rollout is in
    /// progress or halted.
    var userFraction: Double?
    /// Localized "What's new" texts.
    var releaseNotes: [GooglePlayLocalizedTextModel]
    /// In-app update priority, `0`–`5`; `nil` when unset.
    var inAppUpdatePriority: Int?

    /// The staged-rollout fraction to show, only while the rollout is in
    /// progress or halted (Google leaves it unset otherwise).
    var rolloutFraction: Double? {
        guard let userFraction, status == .inProgress || status == .halted else { return nil }
        return userFraction
    }

    /// Release name, falling back to its version codes.
    var displayName: String {
        if let name, !name.trimmingCharacters(in: .whitespaces).isEmpty {
            return name
        }
        if !versionCodes.isEmpty {
            return versionCodes.joined(separator: ", ")
        }
        return String(localized: "Untitled release")
    }
}

/// Raw Google Play release status, with unknown values (e.g.
/// `statusUnspecified` or a future status) folded into `.unknown`.
enum GooglePlayReleaseStatus: String, Codable, Hashable {
    case draft
    case inProgress
    case halted
    case completed
    case unknown

    init(raw: String?) {
        self = raw.flatMap(GooglePlayReleaseStatus.init(rawValue:)) ?? .unknown
    }

    var displayName: String {
        switch self {
        case .draft:      return String(localized: "Draft")
        case .inProgress: return String(localized: "Rolling out")
        case .halted:     return String(localized: "Halted")
        case .completed:  return String(localized: "Completed")
        case .unknown:    return String(localized: "Unknown")
        }
    }

    var color: Color {
        switch self {
        case .draft:      return .gray
        case .inProgress: return .blue
        case .halted:     return .orange
        case .completed:  return .green
        case .unknown:    return .secondary
        }
    }
}

/// A text in one language (e.g. release notes).
struct GooglePlayLocalizedTextModel: Codable, Hashable {
    /// BCP-47 language code.
    let language: String
    var text: String
}
