import SwiftUI

/// Menu-bar commands (Mac, and the iPad hardware-keyboard shortcut overlay),
/// driven by the split view's selection state. The split view publishes its
/// coordinator as a focused scene object, so the commands are disabled while
/// the compact layout is on screen.
struct AppCommands: Commands {

    @FocusedObject private var coordinator: RootSplitCoordinator?

    var body: some Commands {
        SidebarCommands()

        CommandGroup(after: .newItem) {
            Button(String(localized: "Add Account…", comment: "Menu command: adds an App Store Connect account.")) {
                coordinator?.select(.addAccount(.apple))
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])
            .disabled(coordinator == nil)
        }

        CommandGroup(after: .textEditing) {
            Button(String(localized: "Find", comment: "Menu command: focuses the search field of the current list.")) {
                coordinator?.requestSearch()
            }
            .keyboardShortcut("f", modifiers: .command)
            .disabled(coordinator == nil)
        }

        CommandGroup(after: .toolbar) {
            Button(String(localized: "Refresh", comment: "Menu command: syncs every account.")) {
                // User-initiated from the menu bar: not tied to one screen.
                SyncService.shared.syncAll(trigger: .manual, screen: nil)
            }
            .keyboardShortcut("r", modifiers: .command)
        }

        CommandMenu(String(localized: "Go", comment: "Menu bar menu that jumps between the main sections.")) {
            ForEach(RootNavigationShortcut.allCases) { shortcut in
                Button(shortcut.title) {
                    coordinator?.select(shortcut.item)
                }
                .keyboardShortcut(shortcut.key, modifiers: .command)
                .disabled(coordinator == nil)
            }
        }
    }
}

/// The Go menu: sidebar destinations with ⌘1…⌘4 and ⌘, for Settings.
enum RootNavigationShortcut: String, CaseIterable, Identifiable {
    case dashboard
    case inReview
    case awaitingRelease
    case recentReviews
    case settings

    var id: String { rawValue }

    var item: RootSidebarItem {
        switch self {
        case .dashboard:       return .dashboard
        case .inReview:        return .releaseQueue(.inReview)
        case .awaitingRelease: return .releaseQueue(.awaitingRelease)
        case .recentReviews:   return .recentReviews
        case .settings:        return .settings
        }
    }

    var title: String {
        switch self {
        case .dashboard:       return String(localized: "Dashboard", comment: "Split view sidebar item and title of the iPad Home.")
        case .inReview:        return RootReleaseQueue.inReview.title
        case .awaitingRelease: return RootReleaseQueue.awaitingRelease.title
        case .recentReviews:   return String(localized: "Recent Reviews")
        case .settings:        return String(localized: "Settings")
        }
    }

    var key: KeyEquivalent {
        switch self {
        case .dashboard:       return "1"
        case .inReview:        return "2"
        case .awaitingRelease: return "3"
        case .recentReviews:   return "4"
        case .settings:        return ","
        }
    }
}
