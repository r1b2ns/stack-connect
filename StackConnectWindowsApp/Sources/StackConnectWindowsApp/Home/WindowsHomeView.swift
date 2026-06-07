import SwiftCrossUI
import StackHomeCore

// Phase 4 · B1b-2 · T-B4 — the Home content shell (design §2.4).
//
// A ScrollView + VStack (content capped ~860px) laying out, top to bottom:
//   1. toolbar row (T-B3)
//   2. sync banner slot (shown while syncing)
//   3. provider cards slot (minimal tappable cards; full cards = T-B5)
//   4. widgets slot (empty-state or a list of active widgets; widget views = T-C)
//
// Everything binds to the shared core state via `model.state`. The provider and
// widget cells are deliberately lightweight placeholders so this task is just
// the shell — the real card/widget visuals land in T-B5 / T-C*.

struct WindowsHomeView: View {
    let model: WindowsHomeModel
    let coordinator: WindowsHomeCoordinator

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                WindowsToolbarView(
                    title: "StackConnect",
                    onSync: { model.triggerSync() },
                    onCustomizeWidgets: { coordinator.push(.customizeWidgets) }
                )

                syncBannerSlot
                providerGridSlot
                widgetsSlot

                Spacer()
            }
            .padding(16)
            .frame(maxWidth: 860)
        }
    }

    // MARK: - Sync banner slot (US-003)

    @ViewBuilder
    private var syncBannerSlot: some View {
        if model.state.syncState.isSyncing {
            WindowsSyncBannerView(syncState: model.state.syncState)
        }
    }

    // MARK: - Provider cards slot (US-001 / US-002)

    @ViewBuilder
    private var providerGridSlot: some View {
        VStack(spacing: 8) {
            ForEach(model.state.providers) { provider in
                providerCard(provider)
            }
            settingsCard
        }
    }

    private func providerCard(_ provider: ProviderType) -> some View {
        HStack(spacing: 12) {
            Text(glyph(for: provider))
                .foregroundColor(color(named: provider.colorName))
            Text(provider.displayName)
                .fontWeight(.semibold)
            Spacer()
            Text(">")
                .foregroundColor(.gray)
        }
        .padding(12)
        .background(Color(white: 0.95))
        .cornerRadius(8)
        .onTapGesture {
            coordinator.push(.accountsList(provider))
        }
    }

    private var settingsCard: some View {
        HStack(spacing: 12) {
            Text("⚙")
            Text("Settings")
                .fontWeight(.semibold)
            Spacer()
            Text(">")
                .foregroundColor(.gray)
        }
        .padding(12)
        .background(Color(white: 0.95))
        .cornerRadius(8)
        .onTapGesture {
            coordinator.push(.settings)
        }
    }

    // MARK: - Widgets slot (US-006 / US-007)

    @ViewBuilder
    private var widgetsSlot: some View {
        if model.state.widgets.isEmpty {
            widgetsEmptyState
        } else {
            VStack(spacing: 8) {
                ForEach(model.state.widgets, id: \.id) { widget in
                    widgetCard(widget)
                }
            }
        }
    }

    private var widgetsEmptyState: some View {
        VStack(spacing: 8) {
            Text("[#]")
            Text("No widgets yet")
                .fontWeight(.semibold)
            Text("Add widgets to see your apps in review, awaiting release, and recent reviews.")
                .foregroundColor(.gray)
            Button("Add Widgets") {
                coordinator.push(.customizeWidgets)
            }
        }
        .padding(16)
        .background(Color(white: 0.95))
        .cornerRadius(8)
    }

    private func widgetCard(_ widget: any HomeWidget) -> some View {
        HStack(spacing: 12) {
            Text(glyph(for: widget.kind))
            Text(widget.kind.displayName)
                .fontWeight(.semibold)
            Spacer()
        }
        .padding(16)
        .background(Color(white: 0.95))
        .cornerRadius(8)
    }

    // MARK: - Icon + color substitution (design §2.8)

    private func glyph(for provider: ProviderType) -> String {
        switch provider {
        case .apple: return "ASC"
        case .firebase: return "🔥"
        case .googlePlay: return "▶"
        }
    }

    private func glyph(for kind: HomeWidgetKind) -> String {
        switch kind {
        case .inReview: return "🔍"
        case .awaitingRelease: return "📤"
        case .recentReviews: return "💬"
        }
    }

    private func color(named name: String) -> Color {
        switch name {
        case "blue": return .blue
        case "orange": return .orange
        case "green": return .green
        case "yellow": return .yellow
        case "red": return .red
        case "purple": return .purple
        case "gray": return .gray
        default: return .gray
        }
    }
}
