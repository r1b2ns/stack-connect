import LinkPresentation
import UIKit

/// Text activity item for `UIActivityViewController` that also controls how the
/// share is presented:
/// - `previewTitle` / `previewURL` / `previewIcon` feed the share sheet's header
///   (`LPLinkMetadata`), e.g. to show who the message is meant for;
/// - `subject` pre-fills the subject of activities that support one (e.g. Mail).
///
/// The shared payload itself is always just `text`. Pair it with
/// `View.stackShareSheet(item:activityItems:)`.
final class StackShareTextItemSource: NSObject, UIActivityItemSource {

    let text: String
    let subject: String?
    let previewTitle: String?
    let previewURL: URL?
    let previewIcon: UIImage?

    init(
        text: String,
        subject: String? = nil,
        previewTitle: String? = nil,
        previewURL: URL? = nil,
        previewIcon: UIImage? = nil
    ) {
        self.text = text
        self.subject = subject
        self.previewTitle = previewTitle
        self.previewURL = previewURL
        self.previewIcon = previewIcon
    }

    // MARK: - UIActivityItemSource

    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        text
    }

    func activityViewController(
        _ activityViewController: UIActivityViewController,
        itemForActivityType activityType: UIActivity.ActivityType?
    ) -> Any? {
        text
    }

    func activityViewController(
        _ activityViewController: UIActivityViewController,
        subjectForActivityType activityType: UIActivity.ActivityType?
    ) -> String {
        subject ?? ""
    }

    func activityViewControllerLinkMetadata(_ activityViewController: UIActivityViewController) -> LPLinkMetadata? {
        // Without a title the system's default text preview is better than an empty header.
        guard let previewTitle else { return nil }

        let metadata = LPLinkMetadata()
        metadata.title = previewTitle
        if let previewURL {
            // Shows the destination host under the title (e.g. appstoreconnect.apple.com).
            metadata.originalURL = previewURL
            metadata.url = previewURL
        }
        if let previewIcon {
            metadata.iconProvider = NSItemProvider(object: previewIcon)
        }
        return metadata
    }
}
