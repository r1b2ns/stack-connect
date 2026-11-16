import Foundation

// MARK: - Access state

/// Where a Google Play user stands with the developer account (`User.accessState`).
///
/// Unknown-safe: a value Google adds later decodes to `.unknown`, keeping the raw
/// string, so a list never fails to load over a new state.
enum GooglePlayUserAccessState: Hashable, Sendable {
    case invited
    case invitationExpired
    case accessGranted
    case accessExpired
    case unknown(String?)

    init(rawValue: String?) {
        switch rawValue {
        case "INVITED":            self = .invited
        case "INVITATION_EXPIRED": self = .invitationExpired
        case "ACCESS_GRANTED":     self = .accessGranted
        case "ACCESS_EXPIRED":     self = .accessExpired
        default:                   self = .unknown(rawValue)
        }
    }

    var rawValue: String? {
        switch self {
        case .invited:              return "INVITED"
        case .invitationExpired:    return "INVITATION_EXPIRED"
        case .accessGranted:        return "ACCESS_GRANTED"
        case .accessExpired:        return "ACCESS_EXPIRED"
        case .unknown(let raw):     return raw
        }
    }

    var displayName: String {
        switch self {
        case .invited:            return String(localized: "Invited", comment: "Google Play user access state: invitation sent, not accepted yet.")
        case .invitationExpired:  return String(localized: "Invitation expired", comment: "Google Play user access state.")
        case .accessGranted:      return String(localized: "Access granted", comment: "Google Play user access state.")
        case .accessExpired:      return String(localized: "Access expired", comment: "Google Play user access state.")
        case .unknown:            return String(localized: "Unknown", comment: "Google Play user access state Google didn't name.")
        }
    }

    /// The invitation hasn't been accepted (sent or expired).
    var isPendingInvitation: Bool {
        self == .invited || self == .invitationExpired
    }

    /// The invitation or the access ran out.
    var isExpired: Bool {
        self == .invitationExpired || self == .accessExpired
    }
}

// MARK: - Grant

/// One user's access to one app (`developers.users.grants`): app-level
/// permissions as raw Google strings (`CAN_REPLY_TO_REVIEWS`, …), kept verbatim
/// so a permission the app doesn't know survives a save.
struct GooglePlayGrantModel: Codable, Hashable, Identifiable, Sendable {
    let packageName: String
    var appLevelPermissions: [String]

    var id: String { packageName }
}

// MARK: - User

/// A user of a Google Play developer account (`developers.users`).
///
/// Google exposes no first / last name: `displayName` is derived from the
/// e-mail for accepted users, and invitations show the address itself.
struct GooglePlayUserModel: Codable, Hashable, Identifiable, Sendable {
    let email: String
    /// Resource name (`developers/{id}/users/{email}`).
    var resourceName: String?
    /// Raw `accessState`; read through `accessState`.
    var accessStateRaw: String?
    /// When the user's access ends, `nil` for never.
    var expirationTime: Date?
    /// Account-level permissions (`CAN_…_GLOBAL`), raw.
    var developerAccountPermissions: [String]
    var grants: [GooglePlayGrantModel]
    /// Google left out permissions the caller can't see (it doesn't manage
    /// every app). Edits are refused for such a user so a save can't drop them.
    var partial: Bool

    var id: String { email.lowercased() }

    init(
        email: String,
        resourceName: String? = nil,
        accessState: GooglePlayUserAccessState = .accessGranted,
        expirationTime: Date? = nil,
        developerAccountPermissions: [String] = [],
        grants: [GooglePlayGrantModel] = [],
        partial: Bool = false
    ) {
        self.email = email
        self.resourceName = resourceName
        self.accessStateRaw = accessState.rawValue
        self.expirationTime = expirationTime
        self.developerAccountPermissions = developerAccountPermissions
        self.grants = grants
        self.partial = partial
    }

    var accessState: GooglePlayUserAccessState {
        GooglePlayUserAccessState(rawValue: accessStateRaw)
    }

    /// `CAN_MANAGE_PERMISSIONS_GLOBAL`: every permission for every app.
    var isAdmin: Bool {
        developerAccountPermissions.contains(GooglePlayPermissionCatalog.adminPermission)
    }

    /// Google Cloud service accounts (`…@….iam.gserviceaccount.com`).
    var isServiceAccount: Bool {
        GooglePlayUserModel.isServiceAccount(email: email)
    }

    /// Account-level permissions apply to every app.
    var hasAllAppsAccess: Bool {
        !developerAccountPermissions.isEmpty
    }

    /// Whether the users-list badge names the access state ("Invited" /
    /// "Expired") rather than the app scope ("All Apps" / "2 Apps").
    var listBadgeShowsState: Bool {
        switch accessState {
        case .invited, .invitationExpired, .accessExpired: return true
        case .accessGranted, .unknown: return false
        }
    }

    /// Same e-mail, ignoring case (Google treats addresses case-insensitively).
    func matches(email other: String) -> Bool {
        email.caseInsensitiveCompare(other) == .orderedSame
    }

    func grant(for packageName: String) -> GooglePlayGrantModel? {
        grants.first { $0.packageName == packageName }
    }

    /// "Dana Whitfield" from `dana.whitfield@…`, the local part for a service
    /// account (`ci-publisher`), and the whole address for a pending invitation
    /// (Google only learns the name once the person accepts).
    var displayName: String {
        if accessState.isPendingInvitation { return email }
        let local = String(email.split(separator: "@").first ?? Substring(email))
        if isServiceAccount { return local }
        let words = local
            .split(whereSeparator: { $0 == "." || $0 == "_" || $0 == "-" || $0 == "+" })
            .filter { !$0.isEmpty && !$0.allSatisfy(\.isNumber) }
        guard !words.isEmpty else { return email }
        return words.map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }

    /// Up to two letters for the avatar ("DW"; "ci" for a service account).
    var initials: String {
        let local = String(email.split(separator: "@").first ?? Substring(email))
        if isServiceAccount { return String(local.prefix(2)).lowercased() }
        let words = local
            .split(whereSeparator: { $0 == "." || $0 == "_" || $0 == "-" || $0 == "+" })
            .filter { !$0.isEmpty }
        if words.count >= 2 {
            return words.prefix(2).compactMap(\.first).map { String($0).uppercased() }.joined()
        }
        return String(local.prefix(2)).uppercased()
    }

    static func isServiceAccount(email: String) -> Bool {
        let domain = email.split(separator: "@").last.map { $0.lowercased() } ?? ""
        return domain.hasSuffix("gserviceaccount.com") || domain.contains(".iam.")
    }
}

// MARK: - Cache

/// The account's users, cached for offline-first display
/// (`googleplay-users.{accountId}`). It holds e-mail addresses, so
/// `AccountCascadeDeleter` removes it with the account.
struct GooglePlayUsersCache: Codable, Sendable {
    static let keyPrefix = "googleplay-users"

    let accountId: String
    var users: [GooglePlayUserModel]
    var fetchedAt: Date

    static func cacheKey(accountId: String) -> String {
        "\(keyPrefix).\(accountId)"
    }

    var cacheKey: String { Self.cacheKey(accountId: accountId) }
}

// MARK: - Developer ID

/// The numeric Play Console developer account ID (`developers/{id}`).
///
/// Google offers no way to discover it, but it isn't secret: it is in every
/// Play Console URL (`…/developers/4829103756618820931/…`), so a pasted URL is
/// accepted too.
enum GooglePlayDeveloperId {

    /// The ID in `input` (digits, or a Play Console URL), `nil` when there is none.
    static func normalized(_ input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.allSatisfy(\.isASCIIDigit) { return trimmed }
        // ".../developers/<digits>/..." from a pasted Play Console URL.
        if let range = trimmed.range(of: #"developers/(\d+)"#, options: .regularExpression) {
            let digits = trimmed[range].drop(while: { !$0.isASCIIDigit })
            return digits.isEmpty ? nil : String(digits)
        }
        return nil
    }

    /// True for an empty input (the field is optional) or a valid ID.
    static func isAcceptable(_ input: String) -> Bool {
        input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || normalized(input) != nil
    }
}

private extension Character {
    var isASCIIDigit: Bool { isASCII && isNumber }
}

// MARK: - Cache store

/// Reads and updates one account's users cache, so a write made on a user's
/// detail shows in the list on the way back without a new request. Failures
/// are logged and swallowed (the next load re-reads Google).
struct GooglePlayUsersCacheStore: Sendable {

    let storage: PersistentStorable
    let accountId: String

    var key: String { GooglePlayUsersCache.cacheKey(accountId: accountId) }

    func load() async -> GooglePlayUsersCache? {
        do {
            return try await storage.fetch(GooglePlayUsersCache.self, id: key)
        } catch {
            Log.print.error("[GooglePlayUsers] Cache load failed: \(error.localizedDescription)")
            return nil
        }
    }

    func save(_ users: [GooglePlayUserModel]) async {
        do {
            try await storage.save(GooglePlayUsersCache(accountId: accountId, users: users, fetchedAt: Date()), id: key)
        } catch {
            Log.print.error("[GooglePlayUsers] Cache save failed: \(error.localizedDescription)")
        }
    }

    /// Replaces (or adds) `user` in the cache, keeping the others.
    func upsert(_ user: GooglePlayUserModel) async {
        guard let cache = await load() else { return }
        var users = cache.users.filter { $0.id != user.id }
        users.append(user)
        await save(users)
    }

    func remove(email: String) async {
        guard let cache = await load() else { return }
        await save(cache.users.filter { !$0.matches(email: email) })
    }
}
