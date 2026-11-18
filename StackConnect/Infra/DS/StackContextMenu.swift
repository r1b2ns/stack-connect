import SwiftUI

extension View {
    /// A context menu only where it is enabled: rows that offer their actions
    /// as swipe actions on iPhone also get them on secondary click on iPad and
    /// Mac, without adding a long-press menu to the compact layout.
    @ViewBuilder
    func stackContextMenu<MenuItems: View>(
        isEnabled: Bool,
        @ViewBuilder menuItems: () -> MenuItems
    ) -> some View {
        if isEnabled {
            contextMenu(menuItems: menuItems)
        } else {
            self
        }
    }
}
