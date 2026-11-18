import SwiftUI

/// Full-screen error: "Error" with the message, an optional Retry (the primary
/// action, listed first), any screen-specific `actions`, and a Share Error
/// button that sends the error report through the system share sheet (see
/// `StackErrorShareLink`).
///
/// For errors shown above content that stays on screen, use
/// `StackInlineErrorSection` instead.
///
/// Analytics: sends `error_shown` (`presentation=full_screen`, plus
/// `error_category` when the caller knows it) on the tracked screen around it
/// (`\.analyticsScreen`), and tracks Retry / Share Error taps there.
struct StackErrorContentView<Actions: View>: View {

    let message: String
    let reportContext: ErrorReportContext
    let onRetry: (() -> Void)?
    /// The error's category, when the caller still has the error (never
    /// derived from the message).
    let errorCategory: AnalyticsErrorCategory?
    let actions: Actions

    @Environment(\.analytics) private var analytics
    @Environment(\.analyticsScreen) private var screen

    init(
        message: String,
        reportContext: ErrorReportContext,
        errorCategory: AnalyticsErrorCategory? = nil,
        onRetry: (() -> Void)? = nil,
        @ViewBuilder actions: () -> Actions
    ) {
        self.message = message
        self.reportContext = reportContext
        self.errorCategory = errorCategory
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
                Button(String(localized: "Retry")) {
                    if let screen {
                        analytics.track(.buttonTap(.tryAgain, on: screen))
                    }
                    onRetry()
                }
            }
            actions
            StackErrorShareLink(message: message, context: reportContext)
        }
        .trackErrorShown(message, presentation: .fullScreen, category: errorCategory)
    }
}

extension StackErrorContentView where Actions == EmptyView {

    /// Full-screen error without screen-specific actions.
    init(
        message: String,
        reportContext: ErrorReportContext,
        errorCategory: AnalyticsErrorCategory? = nil,
        onRetry: (() -> Void)? = nil
    ) {
        self.init(message: message, reportContext: reportContext, errorCategory: errorCategory, onRetry: onRetry) {
            EmptyView()
        }
    }
}
