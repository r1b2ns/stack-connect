import Foundation

/// Shared App Group used by the main app and the widget extension to access the
/// same on-device SwiftData store.
///
/// The identifier is the `APP_GROUP_IDENTIFIER` build setting
/// (`Configs/*.xcconfig`, overridable in the git-ignored `Configs/Local.xcconfig`),
/// which is expanded into both `.entitlements` files and into the
/// `AppGroupIdentifier` Info.plist key of the app and the widget. Reading it from
/// the running bundle keeps the code in step with the entitlement, so a
/// contributor's own App Group works without editing source.
public enum AppGroup {
    /// The Info.plist key that carries the App Group identifier.
    public static let infoPlistKey = "AppGroupIdentifier"

    /// The maintainer's App Group, used when the bundle doesn't carry the key
    /// (e.g. a host without the generated Info.plist entry).
    public static let defaultIdentifier = "group.zeroSixteen.stackconnect"

    /// The App Group identifier of the running app or widget.
    public static let identifier: String = identifier(infoDictionary: Bundle.main.infoDictionary)

    /// Resolves the identifier from an Info.plist dictionary, falling back to
    /// ``defaultIdentifier`` when the key is missing, empty, or was left
    /// unexpanded (a literal `$(...)` means the build setting wasn't defined).
    public static func identifier(infoDictionary: [String: Any]?) -> String {
        guard let value = (infoDictionary?[infoPlistKey] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !value.isEmpty,
            !value.contains("$(")
        else { return defaultIdentifier }
        return value
    }
}
