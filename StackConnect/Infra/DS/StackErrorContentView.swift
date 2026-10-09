import SwiftUI

/// Full-screen error: "Error" with the message, an optional Retry (the primary
/// action, listed first), any screen-specific `actions`, and a Share Error
/// button that sends the error report through the system share sheet (see
/// `StackErrorShareLink`).
///
/// For errors shown above content that stays on screen, use
/// `StackInlineErrorSection` instead.
struct StackErrorContentView<Actions: View>: View {

    let message: String
    let reportContext: ErrorReportContext
    let onRetry: (() -> Void)?
    let actions: Actions

    init(
        message: String,
        reportContext: ErrorReportContext,
        onRetry: (() -> Void)? = nil,
        @ViewBuilder actions: () -> Actions
    ) {
        self.message = message
        self.reportContext = reportContext
        self.onRetry = onRetry
        self.actions = actions()
    }

    var body: some View {
        ContentUnavailableView {
            Label(String(localized: "Error"), systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            if let onRetry {
                Button(String(localized: "Retry"), action: onRetry)
            }
            actions
            StackErrorShareLink(message: message, context: reportContext)
        }
    }
}

extension StackErrorContentView where Actions == EmptyView {

    /// Full-screen error without screen-specific actions.
    init(message: String, reportContext: ErrorReportContext, onRetry: (() -> Void)? = nil) {
        self.init(message: message, reportContext: reportContext, onRetry: onRetry) {
            EmptyView()
        }
    }
}
