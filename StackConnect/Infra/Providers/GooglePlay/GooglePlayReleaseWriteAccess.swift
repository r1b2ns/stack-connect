import Foundation

/// Who may change a Google Play release (plan R5, R6): the app must be in the
/// account's scope, `googlePlayReleaseWrites` must be ON, and the account needs
/// `edit` on `version` to change a release (rollout, halt, resume, complete,
/// metadata) or `add` to create or promote one.
///
/// Screens use it to show or hide every write entry point; the write flow
/// checks it again right before committing (defense in depth).
enum GooglePlayReleaseWriteAccess {

    enum Kind: Hashable, Sendable {
        /// Change an existing release (`canEdit(.version)`).
        case edit
        /// Create or promote a release (`canAdd(.version)`).
        case add

        init(_ change: GooglePlayReleaseChange) {
            self = change.addsRelease ? .add : .edit
        }
    }

    static func isAllowed(
        _ kind: Kind,
        account: AccountModel,
        app: GooglePlayAppItem,
        featureFlags: FeatureFlags = .shared
    ) -> Bool {
        denialMessage(kind, account: account, app: app, featureFlags: featureFlags) == nil
    }

    /// `nil` when allowed, otherwise the user-facing reason.
    static func denialMessage(
        _ kind: Kind,
        account: AccountModel,
        app: GooglePlayAppItem,
        featureFlags: FeatureFlags = .shared
    ) -> String? {
        guard featureFlags.isEnabled(.googlePlayReleaseWrites) else {
            return String(localized: "Changing Google Play releases isn't available yet.")
        }
        guard account.allowsApp(bundleId: app.packageName) else {
            return String(localized: "This app isn't included in the apps shared with this account.")
        }
        switch kind {
        case .edit where !account.canEdit(.version):
            return String(localized: "You don't have permission to change this app's releases.")
        case .add where !account.canAdd(.version):
            return String(localized: "You don't have permission to create releases for this app.")
        default:
            return nil
        }
    }
}
