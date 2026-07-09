import SwiftUI

// MARK: - Banner

/// A thin top bar shown while the device is offline. Styled after `ToastView`
/// and the Home agreements banner: muted `.bar` material with a secondary
/// foreground. The material background bleeds up behind the status bar while the
/// labelled content stays below the safe area.
struct StackOfflineBanner: View {

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "wifi.slash")
                .font(.caption)
            Text(String(localized: "No internet connection"))
                .font(.caption)
                .fontWeight(.medium)
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background {
            // Tint up into the status-bar region: the fill ignores the top safe
            // area so the color fills behind the status bar, while the HStack
            // above stays within the safe area.
            Rectangle()
                .fill(.bar)
                .ignoresSafeArea(edges: .top)
        }
        .overlay(alignment: .bottom) { Divider() }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Modifier

/// Observes `ConnectivityMonitor` and insets a `StackOfflineBanner` above the
/// content whenever the device is offline. Applied once at the app root — since
/// the whole app is a single `NavigationStack`, that one spot covers every
/// screen.
private struct OfflineBannerModifier: ViewModifier {

    @StateObject private var monitor = ConnectivityMonitor.shared

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .top, spacing: 0) {
                if !monitor.isConnected {
                    StackOfflineBanner()
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.25), value: monitor.isConnected)
    }
}

extension View {
    /// Overlays a global offline banner (a thin top bar) whenever the device
    /// loses connectivity. Apply once at the app root.
    func offlineBanner() -> some View {
        modifier(OfflineBannerModifier())
    }
}
