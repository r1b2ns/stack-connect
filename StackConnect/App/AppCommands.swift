import SwiftUI
import StackProtocols

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
                coordinator?.select(.addAccount(.apple), origin: .menuCommand)
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
                Task { await AppMenuRefresh.perform() }
            }
            .keyboardShortcut("r", modifiers: .command)
        }

        CommandMenu(String(localized: "Go", comment: "Menu bar menu that jumps between the main sections.")) {
            ForEach(RootNavigationShortcut.allCases) { shortcut in
                Button(shortcut.title) {
                    coordinator?.select(shortcut.item, origin: .menuCommand)
                }
                .keyboardShortcut(shortcut.key, modifiers: .command)
                .disabled(coordinator == nil)
            }
        }
    }
}

/// The Refresh menu command (⌘R). Available in both layouts, so it does not
/// go through the split view coordinator.
@MainActor
enum AppMenuRefresh {
    /// Syncs every account (user-initiated from the menu bar: not tied to one
    /// screen), then tracks a screen-less `refresh` action with its outcome and
    /// `source = menu_command`. The `sync` action itself is tracked by
    /// `SyncService` as for any other run.
    static func perform(
        syncService: SyncService = .shared,
        analytics: AnalyticsTracking = AnalyticsService.shared
    ) async {
        await syncService.syncAll(trigger: .manual, screen: nil).value
        analytics.track(.action(
            .refresh,
            on: nil,
            result: syncService.state.lastError == nil ? .success : .failure,
            parameters: [AnalyticsParameterKey.source: .string(AnalyticsNavigationOrigin.menuCommand.rawValue)]
        ))
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
