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

/// The tracked screen a view is shown on, set by `.trackScreen(_:)` for its
/// whole subtree. Shared components (error views, Share Error) read it to
/// attribute their events without every call site passing the screen.
/// `nil` outside any tracked screen.
private struct AnalyticsScreenKey: EnvironmentKey {
    static let defaultValue: AnalyticsScreen? = nil
}

extension EnvironmentValues {
    var analyticsScreen: AnalyticsScreen? {
        get { self[AnalyticsScreenKey.self] }
        set { self[AnalyticsScreenKey.self] = newValue }
    }
}
