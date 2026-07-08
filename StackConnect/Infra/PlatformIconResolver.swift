import Foundation

/// Picks one app-icon URL per platform from a set of builds so a multi-platform
/// app can show each target's real icon (a single `app.iconUrl` only ever
/// represents one target). Builds are inspected newest-first (by `uploadedDate`,
/// nil treated as oldest); for each platform the first build carrying a non-empty
/// `iconUrl` wins. Builds whose platform string doesn't map to an `AppPlatform`
/// are ignored; a platform with no icon-bearing build simply doesn't appear.
enum PlatformIconResolver {
    static func icons(from builds: [BuildModel]) -> [AppPlatform: String] {
        let sorted = builds.sorted { lhs, rhs in
            switch (lhs.uploadedDate, rhs.uploadedDate) {
            case let (left?, right?): return left > right
            case (_?, nil):           return true   // dated build is newer than an undated one
            case (nil, _?):           return false
            case (nil, nil):          return false
            }
        }

        var icons: [AppPlatform: String] = [:]
        for build in sorted {
            guard let raw = build.platform,
                  let platform = AppPlatform.from(raw),
                  icons[platform] == nil,
                  let icon = build.iconUrl,
                  !icon.isEmpty
            else { continue }
            icons[platform] = icon
        }
        return icons
    }
}
