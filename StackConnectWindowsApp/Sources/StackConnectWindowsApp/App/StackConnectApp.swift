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
        }
        .defaultSize(width: 900, height: 660)
    }
}
