import SwiftCrossUI
import StackHomeCore

// Phase 4 · Block F · T-F08 — Add Account Options screen (US-W02, design §F).
//
// Two tappable cards presented after tapping "+" on the accounts list:
//   • "Create New" — always visible; pushes `.createAppleAccount` or
//     `.createFirebaseAccount` depending on the provider type.
//   • "Import .scexport" — only shown for `.apple`; pushes `.importScexport`.
//
// In-content "< Back" pops back to the accounts list. Content is capped at
// 860px (consistent with the rest of the Windows app layout).

struct WindowsAddAccountOptionsView: View {

    /// The provider type this screen was invoked for. Determines which "Create"
    /// route is pushed and whether the Import card is visible.
    let provider: ProviderType
    /// Observed navigation coordinator (push/pop).
    @State private var coordinator: WindowsHomeCoordinator

    init(provider: ProviderType, coordinator: WindowsHomeCoordinator) {
        self.provider = provider
        _coordinator = State(wrappedValue: coordinator)
    }

    var body: some View {
        VStack(spacing: 16) {
            // In-content "< Back" (AC-4, TC-F026).
            WindowsBackButtonView(onBack: { coordinator.pop() })

            HStack {
                Text("Add Account")
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
            }

            // "Create New" card — always shown (AC-1).
            buildCreateNewCard()

            // "Import .scexport" card — only for Apple provider (AC-1, TC-F020).
            if provider == .apple {
                buildImportCard()
            }

            Spacer()
        }
        .padding(16)
        .frame(maxWidth: 860)
    }

    // MARK: - Cards

    /// The "Create New" option card. Pushes `.createAppleAccount` or
    /// `.createFirebaseAccount` depending on the current provider type
    /// (AC-2, TC-F022, TC-F023).
    private func buildCreateNewCard() -> some View {
        WindowsProviderCardView(
            glyph: "+",
            glyphColor: HomeGridCell.color(named: provider.colorName),
            title: "Create New",
            tint: HomeGridCell.color(named: provider.colorName)
        ) {
            switch provider {
            case .apple:
                coordinator.push(.createAppleAccount)
            case .firebase:
                coordinator.push(.createFirebaseAccount)
            case .googlePlay:
                // Google Play is not supported in this flow; guard for exhaustiveness.
                break
            }
        }
    }

    /// The "Import .scexport" option card. Only rendered for `.apple` (the
    /// conditional is in the parent `body`). Pushes `.importScexport` (AC-3, TC-F025).
    private func buildImportCard() -> some View {
        WindowsProviderCardView(
            glyph: "↓",
            glyphColor: .blue,
            title: "Import .scexport",
            tint: .blue
        ) {
            coordinator.push(.importScexport)
        }
    }
}
