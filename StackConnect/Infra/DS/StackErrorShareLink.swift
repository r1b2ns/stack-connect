import SwiftUI

/// Shares an error as a plain-text report (`ErrorShareReport`) through the
/// system share sheet (Copy, Mail, Messages, Slack, …): the message exactly as
/// shown, plus the screen, store, account and app from `context` and the app
/// version, OS and device.
///
/// The report is synchronous text, so it's a plain `ShareLink`; it's built (and
/// timestamped) when the link is rendered, i.e. when the error is shown.
struct StackErrorShareLink: View {

    enum Style {
        /// "Share Error" with its icon — among a full-screen error's actions.
        case titleAndIcon
        /// Compact icon that can sit in a List row without taking over the
        /// row's tap. VoiceOver still reads "Share Error".
        case icon
    }

    let message: String
    let context: ErrorReportContext
    var style: Style = .titleAndIcon

    var body: some View {
        let report = ErrorShareReport.make(message: message, context: context, environment: .current())
        switch style {
        case .titleAndIcon:
            ShareLink(item: report.text, subject: Text(report.subject)) {
                Label(String(localized: "Share Error"), systemImage: "square.and.arrow.up")
            }
            .accessibilityHint(Self.accessibilityHint)
        case .icon:
            ShareLink(item: report.text, subject: Text(report.subject)) {
                Image(systemName: "square.and.arrow.up")
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(String(localized: "Share Error"))
            .accessibilityHint(Self.accessibilityHint)
        }
    }

    private static var accessibilityHint: String {
        String(
            localized: "Shares the error message with app and device details.",
            comment: "Accessibility hint of the Share Error button on error screens."
        )
    }
}
