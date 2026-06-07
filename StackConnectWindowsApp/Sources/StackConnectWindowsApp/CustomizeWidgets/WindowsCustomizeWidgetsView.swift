import Foundation
import SwiftCrossUI
import StackHomeCore

// Phase 4 · B1b-2 · T-C3 — the Customize Widgets screen (US-008, design §2.6).
//
// A PUSHED full-screen route (SwiftCrossUI 0.7 has no sheet, A-2 / §2.3 / TC-052),
// reached from the Home toolbar's "Customize Widgets" button
// (`coordinator.push(.customizeWidgets)`, US-009) and from the widgets empty-state
// card's "Add Widgets" button. The Windows counterpart of the iOS
// CustomizeWidgets screen — same intents through the shared core
// (`HomeViewModel.addWidget/removeWidget/moveWidgets`), different UI framework.
//
// Layout (top → bottom):
//   • header: "< Home" back button + "Customize Widgets" title (design §2.6).
//   • Active section: one row per active widget in stored order
//     `[glyph] [name] [summary] [^] [v] [Remove]`. Up is disabled on the first
//     row, Down on the last (design §2.6). Empty Active → "No active widgets".
//   • Add Widgets section: one row per available (not-yet-active) kind
//     `[glyph] [name] [summary] [Add]`. Hidden entirely when every kind is active.
//
// Every mutation goes through `WindowsHomeModel` → the core `HomeViewModel`, which
// persists the configuration via the file-based Windows prefs `KeyStorable`
// (`home.widget.configurations`) so the order/selection survives restart (AC-9,
// TC-079). No widget data/order is reimplemented here.
//
// Back pops the route (`coordinator.pop()`), returning to Home which re-renders
// against the same shared `model.state` — so the current widget set/order is
// reflected immediately (AC-8, TC-051). `model`/`coordinator` are observed via
// `@State` so this screen redraws as Active/Add change.

struct WindowsCustomizeWidgetsView: View {

    /// Observed core adapter (active widgets + add/remove/move intents).
    @State private var model: WindowsHomeModel
    /// Observed navigation coordinator (for the "< Home" back button).
    @State private var coordinator: WindowsHomeCoordinator

    init(model: WindowsHomeModel, coordinator: WindowsHomeCoordinator) {
        _model = State(wrappedValue: model)
        _coordinator = State(wrappedValue: coordinator)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                header
                activeSection
                addSection
                Spacer()
            }
            .padding(16)
            .frame(maxWidth: 860)
        }
    }

    // MARK: - Header (design §2.6)

    private var header: some View {
        VStack(spacing: 12) {
            // "< Home" back: pops back to Home reflecting the current state
            // (AC-8). Reuses the shared in-content back button.
            HStack {
                Button("< Home") { coordinator.pop() }
                Spacer()
            }

            HStack {
                Text("Customize Widgets")
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
            }
        }
    }

    // MARK: - Active section (US-008 AC-2 / AC-5 / AC-6 / AC-7)

    @ViewBuilder
    private var activeSection: some View {
        VStack(spacing: 8) {
            sectionTitle("Active")

            let widgets = model.state.widgets
            if widgets.isEmpty {
                // AC-7 / TC-050.
                WindowsWidgetEmptyRow(text: "No active widgets")
            } else {
                ForEach(Array(widgets.enumerated()), id: \.element.id) { index, widget in
                    activeRow(widget: widget, index: index, count: widgets.count)
                }
            }
        }
    }

    /// One Active row: `[glyph] [name] [summary] [^] [v] [Remove]`.
    /// Up is disabled on the first row, Down on the last (design §2.6 / TC-048 /
    /// TC-049). The reorder/remove intents go through the shared core.
    private func activeRow(widget: any HomeWidget, index: Int, count: Int) -> some View {
        let kind = widget.kind
        return HStack(spacing: 12) {
            kindLabel(kind)

            // Up: move this widget one slot earlier. `moveWidgets` uses
            // SwiftUI-style `Array.move(fromOffsets:toOffset:)` semantics, so
            // moving element `index` *before* `index-1` is `to: index - 1`.
            Button("^") {
                model.moveWidgets(from: IndexSet(integer: index), to: index - 1)
            }
            .disabled(index == 0)

            // Down: move this widget one slot later. Inserting *after* `index+1`
            // is `to: index + 2` in move semantics.
            Button("v") {
                model.moveWidgets(from: IndexSet(integer: index), to: index + 2)
            }
            .disabled(index == count - 1)

            Button("Remove") {
                model.removeWidget(id: widget.id)
            }
        }
    }

    // MARK: - Add Widgets section (US-008 AC-3 / AC-4)

    @ViewBuilder
    private var addSection: some View {
        let available = model.availableWidgetKinds()
        // Hidden entirely when every kind is active (design §2.6).
        if !available.isEmpty {
            VStack(spacing: 8) {
                sectionTitle("Add Widgets")

                ForEach(available, id: \.id) { kind in
                    HStack(spacing: 12) {
                        kindLabel(kind)
                        Button("Add") {
                            model.addWidget(kind)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Shared pieces

    /// `[glyph] [name] [summary]` + trailing Spacer, shared by Active and Add
    /// rows. The glyph comes from the centralised `HomeWidgetKind.windowsGlyph`
    /// table (design §2.8); name/summary from the core kind tokens.
    private func kindLabel(_ kind: HomeWidgetKind) -> some View {
        HStack(spacing: 8) {
            Text(kind.windowsGlyph)
            VStack(spacing: 2) {
                HStack {
                    Text(kind.displayName)
                        .fontWeight(.medium)
                    Spacer()
                }
                HStack {
                    Text(kind.summary)
                        .foregroundColor(.gray)
                    Spacer()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func sectionTitle(_ text: String) -> some View {
        HStack {
            Text(text)
                .fontWeight(.semibold)
            Spacer()
        }
    }
}
