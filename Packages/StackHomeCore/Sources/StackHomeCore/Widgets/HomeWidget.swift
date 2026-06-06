import Foundation

/// A loadable Home dashboard widget, decoupled from any UI framework.
///
/// This is the **Foundation-pure** protocol shared by the iOS app and the
/// Windows port. View-building is intentionally **not** part of the contract —
/// `makeView()` has been removed (US-010 AC-5). Each platform renders its own
/// views from the same widget data: iOS via a `HomeWidgetViewFactory`
/// (introduced in T-A7), Windows via SwiftCrossUI views over the same result
/// data.
///
/// Conformers expose their kind statically (`static var kind`) and the protocol
/// surfaces `kind`/`id` as instance conveniences through the default extension.
///
/// `@MainActor` is used for Swift Concurrency isolation only (available on the
/// Windows toolchain per A-8) — it carries no SwiftUI/Combine coupling.
@MainActor
public protocol HomeWidget: AnyObject {
    /// The kind this widget renders. Static so the registry can switch on it.
    static var kind: HomeWidgetKind { get }

    /// Stable identity, derived from the configuration. Declared as a
    /// requirement (with a default below) so existential `[any HomeWidget]`
    /// arrays inside constrained generics resolve a concrete witness.
    var id: UUID { get }

    /// Instance-level kind, derived from the static `kind`. Declared as a
    /// requirement (with a default below) for the same reason as `id`.
    var kind: HomeWidgetKind { get }

    /// The persisted configuration backing this widget instance.
    var configuration: HomeWidgetConfiguration { get }

    /// Whether `load()` is currently in flight.
    var isLoading: Bool { get }

    /// Loads (or refreshes) the widget's data from storage.
    func load() async
}

public extension HomeWidget {
    /// Default: stable identity derived from the configuration.
    var id: UUID { configuration.id }

    /// Default: instance-level kind derived from the static `kind`.
    var kind: HomeWidgetKind { Self.kind }
}
