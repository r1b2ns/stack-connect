import SwiftUI

// MARK: - Banner

/// A centered capsule chip shown just below the status bar while the device is
/// offline. Styled after `ToastView`: `.ultraThinMaterial` in a `Capsule` with a
/// soft shadow and a muted secondary foreground.
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
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
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
    /// Overlays a global offline banner (a centered capsule chip below the status
    /// bar) whenever the device loses connectivity. Apply once at the app root.
    func offlineBanner() -> some View {
        modifier(OfflineBannerModifier())
    }
}
