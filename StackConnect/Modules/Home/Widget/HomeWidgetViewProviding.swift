import SwiftUI

/// **Interim iOS-only bridge — to be removed in T-A7.**
///
/// T-A5 removed `makeView()` from the shared `HomeWidget` protocol (US-010 AC-5):
/// view-building is now platform-specific. The Windows port renders its own
/// SwiftCrossUI views; iOS will get a proper `HomeWidgetViewFactory` in T-A7.
///
/// Until that factory lands, this small iOS-side protocol re-adds the
/// `makeView()` requirement so the existing concrete widgets and
/// `HomeWidgetContainerView` keep compiling and rendering exactly as before,
/// with no runtime change. The 3 concrete widget data types still live in the
/// app target (they move to core in T-A6).
///
/// It deliberately does **not** inherit from `StackHomeCore.HomeWidget`: a
/// refinement-via-existential-cast over the `@MainActor` core protocol (whose
/// `kind`/`id` come from a protocol extension) tripped a Swift compiler
/// conformance-path crash. Keeping it standalone avoids that while still letting
/// the registry widgets opt in.
@MainActor
protocol HomeWidgetViewProviding: AnyObject {
    func makeView() -> AnyView
}
