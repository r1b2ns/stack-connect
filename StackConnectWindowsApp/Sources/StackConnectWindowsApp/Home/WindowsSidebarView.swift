import Foundation
import SwiftCrossUI
import StackHomeCore

// Phase 4 · B1b-2 — the persistent Home sidebar, extracted from WindowsHomeView.
//
// Previously the sidebar lived inside WindowsHomeView, so pushing any route
// (which replaces the whole right-hand pane in RootView) made it disappear. The
// sidebar is now a standalone view hosted by RootView's persistent shell, so it
// stays visible on every screen — including the "+ Add" options and the apps
// list — while only the right-hand pane swaps.
//
// Visuals are unchanged from the former `sidebarPanel`/`buildSidebarItem`:
// 200px fixed width, gray 0.04 background, 8pt padding, three items (Home,
// App Store Connect, Settings) with Dividers between and a trailing Spacer.
//
// Behavior change: tapping an item now `popToRoot()`s FIRST, then sets the
// section. Without the pop, selecting a section from within a pushed route
// would leave the old pushed screen on top of the right pane; popping to root
// guarantees the selection navigates back to that section's root.

struct WindowsSidebarView: View {
    let coordinator: WindowsHomeCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            buildSidebarItem(
                section: .home,
                glyph: "🏠",
                title: "Home",
                tint: .purple
            )
            Divider()
                .padding(.vertical, 4)
            buildSidebarItem(
                section: .appStoreConnect,
                glyph: "ASC",
                title: "App Store Connect",
                tint: .blue
            )
            Divider()
                .padding(.vertical, 4)
            buildSidebarItem(
                section: .settings,
                glyph: "⚙",
                title: "Settings",
                tint: .gray
            )
            Spacer()
        }
        .padding(8)
        .frame(width: 200)
        .background(Color.gray.opacity(0.04))
    }

    private func buildSidebarItem(
        section: HomeSection,
        glyph: String,
        title: String,
        tint: Color
    ) -> some View {
        let isSelected = coordinator.sidebarSection == section
        return HStack(spacing: 8) {
            Text(glyph)
                .fontWeight(.bold)
                .foregroundColor(tint)
            Text(title)
                .fontWeight(.medium)
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(isSelected ? tint.opacity(0.15) : Color.clear)
        .cornerRadius(6)
        .onTapGesture {
            // Pop any pushed route first so selecting a section from within a
            // pushed screen returns to that section's root rather than leaving
            // the old route on top of the right pane.
            coordinator.popToRoot()
            coordinator.sidebarSection = section
        }
    }
}
