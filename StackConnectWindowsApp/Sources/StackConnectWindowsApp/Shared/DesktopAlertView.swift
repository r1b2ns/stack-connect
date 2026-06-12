import SwiftCrossUI

/// A single option in a ``DesktopAlertView``.
struct DesktopAlertOption {
    let label: String
    let color: Color

    init(_ label: String, color: Color = .gray) {
        self.label = label
        self.color = color
    }
}

/// A custom full-screen modal overlay with a dimmed background and a centered
/// card containing a title, a close (X) button, and a vertical list of option
/// buttons. Clicking any option or the close button dismisses the modal.
///
/// Usage — attach via `.overlay {}` on a parent view, driven by a model flag:
///
/// ```swift
/// .overlay {
///     if model.showAlert {
///         DesktopAlertView(
///             title: "Choose an action",
///             options: [
///                 DesktopAlertOption("Open", color: .blue),
///                 DesktopAlertOption("Delete", color: .red),
///             ],
///             onClose: { model.showAlert = false },
///             onSelect: { label in
///                 model.showAlert = false
///                 handleSelection(label)
///             }
///         )
///     }
/// }
/// ```
struct DesktopAlertView: View {
    /// The title shown at the top of the card.
    let title: String
    /// The vertical list of option buttons.
    let options: [DesktopAlertOption]
    /// Called when the X close button is tapped.
    let onClose: () -> Void
    /// Called with the selected option's label when an option button is tapped.
    let onSelect: (String) -> Void

    var body: some View {
        // Full-area dimmed background + centered card
        VStack(spacing: 0) {
            Spacer()
            HStack(spacing: 0) {
                Spacer()
                buildCard()
                Spacer()
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.5))
    }

    // MARK: - Card

    private func buildCard() -> some View {
        VStack(spacing: 12) {
            // Header: title + close button
            HStack {
                Text(title)
                    .font(.title3)
                    .fontWeight(.semibold)
                Spacer()
                Button("X") {
                    onClose()
                }
                .fontWeight(.bold)
            }

            Divider()

            // Option buttons
            VStack(spacing: 4) {
                ForEach(options, id: \.label) { option in
                    Button(option.label) {
                        onSelect(option.label)
                    }
                    .foregroundColor(option.color)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 8)
                    .background(option.color.opacity(0.08))
                    .cornerRadius(6)
                }
            }
        }
        .padding(20)
        .frame(width: 300)
        .background(Color.gray.opacity(0.15))
        .cornerRadius(12)
        // Stroke MUST live in `.background` (not `.overlay`): on the AppKit
        // backend an overlaid stroke becomes a sibling path view on top of the
        // card that swallows clicks, making the modal's own X/option buttons
        // unclickable. Behind the translucent fill the border still shows through.
        .background {
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.gray.opacity(0.3), style: StrokeStyle(width: 1.0))
        }
    }
}
