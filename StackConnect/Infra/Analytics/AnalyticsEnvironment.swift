import SwiftUI
import StackProtocols

/// SwiftUI access to the analytics tracker. Defaults to `AnalyticsService.shared`;
/// previews and tests override it with `.environment(\.analytics, mock)`.
private struct AnalyticsTrackerKey: EnvironmentKey {
    /// `EnvironmentKey.defaultValue` is a nonisolated requirement while the
    /// tracker is `@MainActor`. SwiftUI resolves environment values on the main
    /// thread, so hopping in with `assumeIsolated` is safe (and traps loudly in
    /// DEBUG if that ever stops being true). Computed rather than stored so no
    /// main-actor state is captured in a nonisolated static.
    static var defaultValue: any AnalyticsTracking {
        MainActor.assumeIsolated { AnalyticsService.shared }
    }
}

extension EnvironmentValues {
    var analytics: any AnalyticsTracking {
        get { self[AnalyticsTrackerKey.self] }
        set { self[AnalyticsTrackerKey.self] = newValue }
    }
}
