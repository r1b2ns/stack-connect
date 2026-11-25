import SwiftUI

// MARK: - Factory

/// The connection guide (flag `accountConnectionGuide`): how the app connects
/// to the service, how credentials are handled, that the code is open, and
/// the ways to connect. Built for one provider and the methods available.
@MainActor
struct ConnectionGuideViewFactory {

    /// The guide shown on its own before the first account connection, over
    /// the account wizard's Credentials step: "Cancel" closes the wizard,
    /// "Skip" (any page) and "Continue" (last page) go on to connect. Inside
    /// the caller's navigation stack.
    static func buildFirstConnection(
        provider: ProviderType,
        methods: [AccountConnectionMethod],
        onContinue: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) -> some View {
        ConnectionGuideView(
            pages: ConnectionGuideContent.pages(for: provider, methods: methods),
            mode: .firstConnection,
            onFinish: onContinue,
            onCancel: onCancel
        )
    }

    /// The guide reopened from the account wizard's "How It Works", as a
    /// sheet with its own navigation stack: "Done" closes it.
    static func buildReopened(
        provider: ProviderType,
        methods: [AccountConnectionMethod],
        onClose: @escaping () -> Void
    ) -> some View {
        NavigationStack {
            ConnectionGuideView(
                pages: ConnectionGuideContent.pages(for: provider, methods: methods),
                mode: .reopened,
                onFinish: onClose,
                onCancel: nil
            )
        }
    }
}

// MARK: - Mode

enum ConnectionGuideMode: Equatable {
    /// Shown on its own before the first connection (Skip / Continue).
    case firstConnection
    /// Opened again from "How It Works" (Done).
    case reopened
}

// MARK: - View

/// The guide's pages in a `StackPagedSteps`, with the mode's toolbar. Every
/// page can be skipped (first connection) or closed (reopened) in one tap.
struct ConnectionGuideView: View {

    let pages: [ConnectionGuidePage]
    let mode: ConnectionGuideMode
    let onFinish: () -> Void
    var onCancel: (() -> Void)?

    @State private var currentPage = 0

    var body: some View {
        StackPagedSteps(
            pageCount: pages.count,
            currentPage: $currentPage,
            finishTitle: mode == .firstConnection ? String(localized: "Continue") : String(localized: "Done"),
            finishButton: mode == .firstConnection ? .continue : .done,
            trackingScreen: .connectionGuide,
            onFinish: onFinish
        ) { index in
            buildPage(pages[index])
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(String(localized: "How It Works",
                                comment: "Title of the connection guide, and of the Add Account entry that reopens it."))
        .navigationBarTitleDisplayMode(.inline)
        .trackScreen(.connectionGuide)
        .toolbar { buildToolbar() }
    }

    // MARK: - Page

    private func buildPage(_ page: ConnectionGuidePage) -> some View {
        StackStepPage(systemImage: page.systemImage, title: page.title, message: page.message) {
            if !page.items.isEmpty {
                StackTrustCard(items: page.items)
            }

            if !page.notes.isEmpty {
                StackTrustCard(items: page.notes)
            }

            if !page.links.isEmpty {
                buildLinks(page.links)
            }

            if let footnote = page.footnote {
                Text(footnote)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func buildLinks(_ links: [StackExternalLinkItem]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(links.enumerated()), id: \.element.id) { index, link in
                if index > 0 {
                    Divider()
                }
                StackExternalLink(link, screen: .connectionGuide)
                    .padding(.vertical, 14)
            }
        }
        .padding(.horizontal, 16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private func buildToolbar() -> some ToolbarContent {
        if mode == .firstConnection {
            ToolbarItem(placement: .cancellationAction) {
                StackTrackedButton(String(localized: "Cancel"), button: .cancel, on: .connectionGuide) {
                    onCancel?()
                }
            }
            ToolbarItem(placement: .primaryAction) {
                StackTrackedButton(String(localized: "Skip", comment: "Connection guide: skips the rest of the guide and goes on to add the account."),
                                   button: .skip, on: .connectionGuide, action: onFinish)
            }
        }
        if mode == .reopened {
            ToolbarItem(placement: .confirmationAction) {
                StackTrackedButton(String(localized: "Done"), button: .done, on: .connectionGuide, action: onFinish)
            }
        }
    }
}

#Preview("First connection") {
    NavigationStack {
        ConnectionGuideViewFactory.buildFirstConnection(
            provider: .apple,
            methods: [.apiKey, .appleIdSignIn],
            onContinue: {},
            onCancel: {}
        )
    }
}

#Preview("Reopened, one method") {
    ConnectionGuideViewFactory.buildReopened(provider: .firebase, methods: [.serviceAccount], onClose: {})
}
