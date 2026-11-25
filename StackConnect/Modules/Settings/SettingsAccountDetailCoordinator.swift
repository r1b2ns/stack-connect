import SwiftUI

/// Presentations of the account detail: the wizard (reconnect), the export
/// sheet and its feedback. Pushes go through the enclosing `HomeCoordinator`.
@MainActor
final class SettingsAccountDetailCoordinator: ObservableObject {

    @Published var wizardEntry: AccountWizardEntry?
    @Published var isShowingExport = false
    @Published var exportFeedback: ExportFeedback?

    func presentReconnect(_ account: AccountModel) {
        wizardEntry = .reconnect(account)
    }

    func dismissWizard() {
        wizardEntry = nil
    }

    func presentExport() {
        isShowingExport = true
    }

    func dismissExport() {
        isShowingExport = false
    }

    func presentExportFeedback(_ feedback: ExportFeedback) {
        exportFeedback = feedback
    }

    func dismissExportFeedback() {
        exportFeedback = nil
    }
}

// MARK: - ExportFeedback

struct ExportFeedback: Identifiable {
    let id = UUID()
    let type: FeedbackType
    let image: String
    let title: String
    let message: String
}
