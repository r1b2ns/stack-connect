import Foundation

/// Who may open a section of a Google Play app: the app must be in the
/// account's per-app scope (`AccountModel.allowsApp`) and the account needs the
/// section's view rule. The menu checks it before navigating and every section
/// ViewModel checks it again before reading (defense in depth), so a denied
/// section never opens a Play edit.
enum GooglePlayAppSectionAccess {

    /// `nil` when allowed, otherwise the user-facing reason.
    static func denialMessage(
        account: AccountModel,
        app: GooglePlayAppItem,
        resource: AccountRuleResource
    ) -> String? {
        guard account.allowsApp(bundleId: app.packageName) else {
            return String(localized: "This app isn't included in the apps shared with this account.")
        }
        guard account.canView(resource) else {
            switch resource {
            case .review: return String(localized: "You don't have permission to view ratings and reviews.")
            default:      return String(localized: "You don't have permission to view this app's details.")
            }
        }
        return nil
    }
}
