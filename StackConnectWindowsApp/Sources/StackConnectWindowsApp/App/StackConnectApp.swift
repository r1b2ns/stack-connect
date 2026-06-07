import DefaultBackend
import SwiftCrossUI
import Foundation

// Phase 4 · B1b-2 · T-B2 — the real app entry.
//
// Replaces the B1b-1 smoke-counter window. `init()` runs the B2 bootstrap
// (SQLite store + file-based prefs) and injects the shared core `HomeViewModel`
// into the SwiftCrossUI `WindowsHomeModel` adapter. The window hosts the route
// switch (Home at root, pushed destinations on top). On Windows this renders
// through WinUI; on macOS through AppKit (so it also builds/runs on the host).
//
// SCUI_DEFAULT_BACKEND=WinUIBackend is honored by DefaultBackend itself on the
// VM (set by Test-WindowsPort.ps1 before the build); nothing to do here.
@main
struct StackConnectApp: App {

    let model: WindowsHomeModel

    init() {
        do {
            model = WindowsHomeModel(environment: try Bootstrap.makeEnvironment())
        } catch {
            // The store directory/database could not be created — unrecoverable
            // at launch. Surface it loudly rather than starting half-wired.
            fatalError("StackConnect bootstrap failed: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup("StackConnect") {
            RootView(model: model)
                // T-D4 (design §2.9): enforce the minimum window size. In
                // SwiftCrossUI the window's minimum is derived from the content's
                // layout size when proposed `.zero`, so a min-size frame on the
                // root content makes the probing pass report ≥ 680×520 — which
                // the backend then sets as the window's `contentMinSize`. This is
                // what blocks resizing below the minimum (AC-4 / TC-077) and
                // guarantees the narrow layout is only ever exercised at ≥ 680px.
                .frame(minWidth: 680, minHeight: 520)
        }
        .defaultSize(width: 900, height: 660)
        // `.contentMinSize`: floor at the content's minimum (the 680×520 above),
        // no maximum — the window grows freely past the content (design: "no
        // max"), keeping the 860-capped content centered in the extra space.
        .windowResizability(.contentMinSize)
    }
}
