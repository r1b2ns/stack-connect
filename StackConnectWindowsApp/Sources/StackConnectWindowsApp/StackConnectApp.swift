import DefaultBackend
import SwiftCrossUI

// Phase 4 · B1b-1 — the smallest possible SwiftCrossUI window.
//
// Its only job is to validate the backend end-to-end on the VM: that
// SwiftCrossUI + the WinUI backend build, that a window opens, and that event
// handling works (the counter), before any real screens are wired in. On
// Windows this renders through WinUI; on macOS through AppKit (so it also builds
// on the host). Real screens (accounts list → add → detail) land on top in
// later B1b steps, reusing the Foundation-pure ViewModels and the B2 bootstrap.
@main
struct StackConnectApp: App {

    @State var count = 0

    var body: some Scene {
        WindowGroup("StackConnect") {
            VStack(spacing: 16) {
                Text("StackConnect")
                Text("SwiftCrossUI smoke window — Windows port")

                HStack(spacing: 20) {
                    Button("-") { count -= 1 }
                    Text("Count: \(count)")
                    Button("+") { count += 1 }
                }
            }
            .padding()
        }
        .defaultSize(width: 420, height: 220)
    }
}
