import SwiftUI

/// A request to share an error report from a screen that can't host a
/// `ShareLink` (e.g. an alert): see `StackErrorShareAlertButton`.
struct StackErrorShareRequest: Identifiable {
    let id = UUID()
    let report: ErrorShareReport
}

/// "Share Error" among an error alert's actions. Alerts only host plain
/// buttons, so the report is handed to `stackErrorShareSheet(_:)` once the
/// alert has finished closing (UIKit can't present the share sheet from a
/// controller that is still being dismissed).
struct StackErrorShareAlertButton: View {

    let message: String
    let context: ErrorReportContext
    @Binding var request: StackErrorShareRequest?

    var body: some View {
        Button(String(localized: "Share Error")) {
            let report = ErrorShareReport.make(message: message, context: context, environment: .current())
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(450))
                request = StackErrorShareRequest(report: report)
            }
        }
    }
}

extension View {

    /// Presents the system share sheet with the error report of `request`
    /// (its subject pre-fills e.g. Mail), clearing it once dismissed.
    func stackErrorShareSheet(_ request: Binding<StackErrorShareRequest?>) -> some View {
        stackShareSheet(item: request) { request in
            [StackShareTextItemSource(text: request.report.text, subject: request.report.subject)]
        }
    }
}
