import Foundation

/// Single source of truth for the ".scexport" import tutorial.
///
/// Both account-import sheets (`AccountsListView` and `SettingsAccountsView`)
/// reuse these blocks so the step texts are never duplicated. The content is
/// split into a source-device block and a target-device block, which lets
/// ``TutorialGuideView`` render a per-block share button while still exposing a
/// single combined end-to-end message via ``fullShareText``.
enum ImportTutorial {

    /// Ordered tutorial blocks shown inside ``ImportTutorialView``.
    ///
    /// Two blocks (count > 1) so ``TutorialGuideView`` renders per-block headers
    /// and per-block share affordances.
    static var blocks: [TutorialBlock] {
        [
            TutorialBlock(
                icon: "square.and.arrow.up",
                title: String(localized: "On the source device"),
                steps: [
                    TutorialStep(text: String(localized: "Open StackConnect on the source device")),
                    TutorialStep(text: String(localized: "Go to Settings → select the account → Export and set a password")),
                    TutorialStep(text: String(localized: "Share the generated .scexport file (AirDrop, Files, email, etc.)"))
                ]
            ),
            TutorialBlock(
                icon: "square.and.arrow.down",
                title: String(localized: "On the target device"),
                steps: [
                    TutorialStep(text: String(localized: "Open StackConnect on the target device (iPhone, iPad, or the Windows app)")),
                    TutorialStep(text: String(localized: "Tap Add Account → Import")),
                    TutorialStep(text: String(localized: "Select the .scexport file and enter the password you set"))
                ]
            )
        ]
    }

    /// Combined, end-to-end shareable text.
    ///
    /// A localized header line followed by each block rendered through
    /// ``TutorialGuideView/makeShareText(for:)`` so the per-block share text and
    /// this combined message stay in sync from the same data.
    static var fullShareText: String {
        let header = String(localized: "How to import an account into StackConnect")
        let body = blocks
            .map { TutorialGuideView.makeShareText(for: $0) }
            .joined(separator: "\n\n")
        return "\(header)\n\n\(body)"
    }
}
