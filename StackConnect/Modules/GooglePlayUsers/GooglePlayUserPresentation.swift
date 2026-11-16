import SwiftUI

/// How a Google Play user is drawn (prototype 16 / 17): avatar tone, list badge
/// and state badge. Shared by the users list and the user detail.
extension GooglePlayUserModel {

    /// Red for admins, orange while invited, gray when expired, green for
    /// service accounts, blue otherwise.
    var avatarTint: Color {
        if isServiceAccount { return .green }
        switch accessState {
        case .invited: return .orange
        case .invitationExpired, .accessExpired: return .gray
        default: return isAdmin ? .red : .blue
        }
    }

    func avatar(size: CGFloat = 36) -> StackAvatar {
        StackAvatar(initials: initials, tint: avatarTint, size: size)
    }

    /// The trailing badge of a list row: the state while it isn't granted,
    /// otherwise the scope ("All Apps" / "2 Apps").
    var listBadge: StackPersonRow.Badge? {
        switch accessState {
        case .invited:
            return .init(title: String(localized: "Invited", comment: "Google Play users list badge."), color: .orange)
        case .invitationExpired, .accessExpired:
            return .init(title: String(localized: "Expired", comment: "Google Play users list badge."), color: .red)
        default:
            if hasAllAppsAccess {
                return .init(title: String(localized: "All Apps"), color: .blue)
            }
            if !grants.isEmpty {
                return .init(title: grants.count == 1
                             ? String(localized: "1 App", comment: "Google Play users list badge: access to one app.")
                             : String(localized: "\(grants.count) Apps", comment: "Google Play users list badge: access to several apps."),
                             color: .gray)
            }
            return nil
        }
    }

    /// The access state under the name in the user detail header.
    var stateBadge: StackPersonRow.Badge {
        let color: Color
        switch accessState {
        case .accessGranted: color = .green
        case .invited: color = .orange
        case .invitationExpired, .accessExpired: color = .red
        case .unknown: color = .gray
        }
        return .init(title: accessState.displayName, color: color)
    }

    /// The line under the name in the list: the e-mail, or for an invitation
    /// (whose name already is the e-mail) where it stands.
    var listSubtitle: String {
        switch accessState {
        case .invited: return String(localized: "Invitation sent", comment: "Google Play users list: invitation not accepted yet.")
        case .invitationExpired: return String(localized: "Invitation expired")
        default: return email
        }
    }
}

extension GooglePlayGrantModel {

    /// "Reply to reviews", or "4 permissions" ("View app information" not counted).
    var summary: String {
        let view = GooglePlayPermissionCatalog.viewAppInformation
        let meaningful = appLevelPermissions.filter { value in
            value != view.appLevel && !view.legacyValues.contains(value)
        }
        switch meaningful.count {
        case 0: return view.appName
        case 1: return GooglePlayPermissionCatalog.displayName(forValue: meaningful[0], level: .app)
        default: return String(localized: "\(meaningful.count) permissions", comment: "Google Play: number of permissions on one app.")
        }
    }
}
