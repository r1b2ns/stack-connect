import SwiftUI

/// The wizard's steps are driven by its ViewModel (the step engine): there is
/// no route to push. The coordinator owns the sheets around the steps and the
/// way out, so callers only hand over what closing means.
@MainActor
final class AccountWizardCoordinator: ObservableObject {

    /// The `.scexport` file picker of an import.
    @Published var isShowingFileImporter = false
    /// "How to import?".
    @Published var isShowingImportTutorial = false

    private let onClose: () -> Void

    init(onClose: @escaping () -> Void) {
        self.onClose = onClose
    }

    func presentFileImporter() {
        isShowingFileImporter = true
    }

    func presentImportTutorial() {
        isShowingImportTutorial = true
    }

    /// Cancel, or "View in List" on the done screen. The caller dismisses the
    /// wizard; the lists reload on `AccountsChange`.
    func close() {
        onClose()
    }
}
