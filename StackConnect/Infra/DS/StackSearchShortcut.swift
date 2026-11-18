import SwiftUI

// MARK: - Environment

private struct StackSearchRequestKey: EnvironmentKey {
    static let defaultValue = 0
}

extension EnvironmentValues {
    /// Bumped by the Find command (⌘F): searchable screens that opt in with
    /// `stackSearchShortcutFocus()` move the focus to their search field.
    var stackSearchRequest: Int {
        get { self[StackSearchRequestKey.self] }
        set { self[StackSearchRequestKey.self] = newValue }
    }
}

// MARK: - Modifier

extension View {
    /// Focuses this screen's `.searchable` field when the Find command fires.
    /// Needs iOS 18 (`searchFocused`); a no-op before.
    func stackSearchShortcutFocus() -> some View {
        modifier(StackSearchShortcutFocusModifier())
    }
}

private struct StackSearchShortcutFocusModifier: ViewModifier {

    @Environment(\.stackSearchRequest) private var request

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.modifier(FocusingModifier(request: request))
        } else {
            content
        }
    }
}

@available(iOS 18.0, *)
private struct FocusingModifier: ViewModifier {

    let request: Int
    @FocusState private var isFocused: Bool

    func body(content: Content) -> some View {
        content
            .searchFocused($isFocused)
            .onChange(of: request) {
                isFocused = true
            }
    }
}
