import Foundation

/// App-facing analytics interface. Views and ViewModels depend on this
/// protocol only, never on a concrete tracker or vendor SDK.
///
/// Refines `Sendable` so the tracker can be handed out from nonisolated
/// contexts (e.g. a SwiftUI `EnvironmentKey` default value). Every conformer is
/// `@MainActor`-isolated, which makes it implicitly `Sendable`.
@MainActor
public protocol AnalyticsTracking: AnyObject, Sendable {
    /// Whether events are currently being sent (the user's opt-out setting).
    var isEnabled: Bool { get }

    /// Sends `event` when enabled; silently drops it otherwise.
    func track(_ event: AnalyticsEvent)

    /// Turns sending on or off. Turning it off sends one final
    /// `analytics_disabled` event before stopping.
    func setEnabled(_ enabled: Bool)
}
