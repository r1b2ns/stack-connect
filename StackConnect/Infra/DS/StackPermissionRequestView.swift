import SwiftUI

/// Full-screen "this needs your go-ahead first" state: a tinted icon, a
/// title, the explanation, an optional notice (what the next page may show),
/// an optional feedback line from the last attempt, a prominent primary
/// button and a plain secondary one.
///
/// Used in place of a screen's content when something must happen before it
/// can load, e.g. granting a Google permission or signing in again
/// (`StackGoogleAccessPromptView`). Tracking of the primary action belongs to
/// the caller; the secondary button is reported as `secondaryButton` on the
/// tracked screen around it (`\.analyticsScreen`).
struct StackPermissionRequestView: View {

    let systemImage: String
    var tint: Color = .accentColor
    let title: String
    let message: String
    var notice: String?
    /// Shown above the buttons, e.g. why the last attempt didn't work.
    var feedback: String?
    /// Shown under the message, e.g. the account the request is for.
    var caption: String?
    let primaryTitle: String
    var isWorking = false
    let onPrimary: () -> Void
    var secondaryTitle: String?
    var secondaryButton: AnalyticsButton = .back
    var onSecondary: (() -> Void)?

    @Environment(\.analytics) private var analytics
    @Environment(\.analyticsScreen) private var screen

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                buildHeader()
                if let notice {
                    buildNotice(notice)
                }
                if let feedback {
                    buildFeedback(feedback)
                }
                buildButtons()
            }
            .frame(maxWidth: 520)
            .padding(.horizontal, 24)
            .padding(.vertical, 32)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    // MARK: - Sections

    private func buildHeader() -> some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 72, height: 72)
                .background(tint.opacity(0.15), in: Circle())
                .accessibilityHidden(true)

            Text(title)
                .font(.title2)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)

            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if let caption {
                Label(caption, systemImage: "person.crop.circle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func buildNotice(_ notice: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(notice)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    private func buildFeedback(_ feedback: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            Text(feedback)
                .font(.footnote)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }

    private func buildButtons() -> some View {
        VStack(spacing: 8) {
            Button(action: onPrimary) {
                HStack(spacing: 8) {
                    if isWorking {
                        ProgressView()
                            .tint(.white)
                    }
                    Text(primaryTitle)
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isWorking)

            if let secondaryTitle, let onSecondary {
                Button(secondaryTitle) {
                    if let screen {
                        analytics.track(.buttonTap(secondaryButton, on: screen))
                    }
                    onSecondary()
                }
                .frame(minHeight: 44)
                .disabled(isWorking)
            }
        }
    }
}

#Preview {
    StackPermissionRequestView(
        systemImage: "slider.horizontal.3",
        title: "Allow Remote Config Access",
        message: "To read and publish your Remote Config, Google needs one more permission.",
        notice: "Google may warn that it hasn't verified StackConnect yet.",
        feedback: "Google didn't grant the permission.",
        caption: "dev@example.com",
        primaryTitle: "Grant Access",
        onPrimary: {},
        secondaryTitle: "Go Back",
        onSecondary: {}
    )
}
