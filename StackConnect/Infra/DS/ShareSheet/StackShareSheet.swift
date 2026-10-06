import SwiftUI
import UIKit

// MARK: - Modifier

extension View {

    /// Presents the native share sheet (`UIActivityViewController`) while `item`
    /// is non-nil, and sets it back to `nil` once the share sheet is dismissed.
    ///
    /// Use this instead of `ShareLink` when the shared content is computed
    /// asynchronously (e.g. a ViewModel publishes a payload after a network call):
    /// set the item when the content is ready and the sheet appears.
    ///
    /// Unlike wrapping `UIActivityViewController` in a SwiftUI `.sheet` — which
    /// renders it inside a full-height sheet with a blank area above it and can
    /// leave an empty sheet behind after an activity runs — the controller is
    /// presented by UIKit itself from the top-most view controller. It therefore
    /// keeps its native half-height/expandable detents, and on iPad it shows as a
    /// centered popover.
    ///
    /// A new item `id` while a share sheet is already on screen replaces it.
    ///
    /// - Parameters:
    ///   - item: The share request. `nil` hides the share sheet.
    ///   - activityItems: Maps the item to the activity items handed to
    ///     `UIActivityViewController` (strings, URLs, `UIActivityItemSource`s, …).
    func stackShareSheet<Item: Identifiable>(
        item: Binding<Item?>,
        activityItems: @escaping (Item) -> [Any]
    ) -> some View {
        background(
            StackShareSheetPresenter(item: item, activityItems: activityItems)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        )
    }
}

// MARK: - Presenter

/// Invisible view controller that anchors the share sheet presentation into the
/// SwiftUI hierarchy and keeps the presented controller in sync with `item`.
private struct StackShareSheetPresenter<Item: Identifiable>: UIViewControllerRepresentable {

    @Binding var item: Item?
    let activityItems: (Item) -> [Any]

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIViewController(context: Context) -> UIViewController {
        let controller = UIViewController()
        controller.view.backgroundColor = .clear
        controller.view.isUserInteractionEnabled = false
        return controller
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        let binding = $item
        context.coordinator.sync(
            item: item,
            anchor: uiViewController,
            makeActivityItems: activityItems,
            onDismiss: { binding.wrappedValue = nil }
        )
    }

    static func dismantleUIViewController(_ uiViewController: UIViewController, coordinator: Coordinator) {
        coordinator.dismissPresented()
    }

    // MARK: - Coordinator

    @MainActor
    final class Coordinator {

        private weak var presentedController: UIActivityViewController?
        private var presentedItemID: Item.ID?

        func sync(
            item: Item?,
            anchor: UIViewController,
            makeActivityItems: @escaping (Item) -> [Any],
            onDismiss: @escaping () -> Void
        ) {
            guard let item else {
                dismissPresented()
                return
            }
            guard item.id != presentedItemID else { return }

            presentedItemID = item.id
            let itemID = item.id
            // Present outside the current SwiftUI update pass.
            Task { @MainActor [weak self, weak anchor] in
                guard let self, self.presentedItemID == itemID else { return }
                guard let anchor, let window = anchor.view.window else {
                    // Not on screen any more: drop the request instead of leaving it stuck.
                    Log.print.error("[ShareSheet] Anchor is not in a window; discarding the share request")
                    self.reset()
                    onDismiss()
                    return
                }
                self.present(
                    activityItems: makeActivityItems(item),
                    itemID: itemID,
                    from: Self.topMostController(in: window) ?? anchor,
                    onDismiss: onDismiss
                )
            }
        }

        func dismissPresented() {
            let controller = presentedController
            reset()
            if let controller, controller.presentingViewController != nil {
                controller.dismiss(animated: true)
            }
        }

        // MARK: - Private

        private func present(
            activityItems: [Any],
            itemID: Item.ID,
            from presenter: UIViewController,
            onDismiss: @escaping () -> Void
        ) {
            // Replace a share sheet that is still showing for a previous item.
            if let previous = presentedController, previous.presentingViewController != nil {
                previous.completionWithItemsHandler = nil
                previous.dismiss(animated: false)
            }

            let controller = UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
            controller.completionWithItemsHandler = { [weak self, weak controller] activityType, completed, _, _ in
                // After the user cancels a chosen activity (e.g. backs out of the
                // Messages composer) iOS keeps the share sheet on screen and calls
                // this handler again when it's finally dismissed — only clear then.
                if activityType != nil, !completed, controller?.viewIfLoaded?.window != nil {
                    return
                }
                guard let self, self.presentedItemID == itemID else { return }
                self.reset()
                onDismiss()
            }

            if let popover = controller.popoverPresentationController {
                popover.sourceView = presenter.view
                popover.sourceRect = CGRect(x: presenter.view.bounds.midX, y: presenter.view.bounds.midY, width: 0, height: 0)
                popover.permittedArrowDirections = []
            }

            presentedController = controller
            presenter.present(controller, animated: true)
        }

        private func reset() {
            presentedController = nil
            presentedItemID = nil
        }

        /// The view controller currently on top of `window`'s presentation stack —
        /// presenting from anything below it would fail if a sheet is already up.
        private static func topMostController(in window: UIWindow) -> UIViewController? {
            var top = window.rootViewController
            while let presented = top?.presentedViewController, !presented.isBeingDismissed {
                top = presented
            }
            return top
        }
    }
}
