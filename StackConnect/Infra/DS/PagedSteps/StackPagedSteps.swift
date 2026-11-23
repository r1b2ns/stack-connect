import SwiftUI

/// A short paged walkthrough: one page at a time (swipe, or Back / Next),
/// a page indicator, and a finish button on the last page.
///
/// Content-agnostic: `page` builds each page (usually a `StackStepPage`).
/// Back and Next only move between pages and are reported as `back` / `next`
/// on `trackingScreen`; the finish button is reported as `finishButton`.
/// Skipping or closing the walkthrough belongs to the caller (a toolbar
/// button), so it is always one tap away whatever the page.
///
/// Used by the connection guide (`ConnectionGuideView`).
struct StackPagedSteps<Page: View>: View {

    let pageCount: Int
    @Binding var currentPage: Int
    let finishTitle: String
    let finishButton: AnalyticsButton
    let trackingScreen: AnalyticsScreen
    let onFinish: () -> Void
    @ViewBuilder let page: (Int) -> Page

    private var isFirstPage: Bool { currentPage <= 0 }
    private var isLastPage: Bool { currentPage >= pageCount - 1 }

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $currentPage) {
                ForEach(0..<pageCount, id: \.self) { index in
                    page(index)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            buildControls()
        }
    }

    // MARK: - Controls

    private func buildControls() -> some View {
        VStack(spacing: 16) {
            StackPageIndicator(pageCount: pageCount, currentPage: currentPage)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { buildButtons() }
                VStack(spacing: 8) { buildButtons() }
            }
            .controlSize(.large)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 16)
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity)
        .background(.bar)
    }

    @ViewBuilder
    private func buildButtons() -> some View {
        StackTrackedButton(.back, on: trackingScreen) {
            move(by: -1)
        } label: {
            Text("Back")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        // Keeps the layout steady on the first page, out of VoiceOver's way.
        .opacity(isFirstPage ? 0 : 1)
        .disabled(isFirstPage)
        .accessibilityHidden(isFirstPage)

        if isLastPage {
            StackTrackedButton(finishButton, on: trackingScreen, action: onFinish) {
                Text(finishTitle)
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        } else {
            StackTrackedButton(.next, on: trackingScreen) {
                move(by: 1)
            } label: {
                Text("Next")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func move(by offset: Int) {
        let target = min(max(currentPage + offset, 0), pageCount - 1)
        guard target != currentPage else { return }
        withAnimation { currentPage = target }
    }
}

// MARK: - Page indicator

/// Dots for the pages of a walkthrough, the current one filled. VoiceOver
/// reads "Page 2 of 4".
struct StackPageIndicator: View {

    let pageCount: Int
    let currentPage: Int

    @ScaledMetric(relativeTo: .caption) private var dotSize: CGFloat = 8

    var body: some View {
        HStack(spacing: dotSize) {
            ForEach(0..<pageCount, id: \.self) { index in
                Circle()
                    .fill(index == currentPage ? Color.accentColor : Color.secondary.opacity(0.3))
                    .frame(width: dotSize, height: dotSize)
            }
        }
        .animation(.default, value: currentPage)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Page \(currentPage + 1) of \(pageCount)",
                                 comment: "Accessibility label of a paged guide's page indicator. Arguments: the current page, the page count."))
    }
}

// MARK: - Page layout

/// The layout of one walkthrough page: a tinted glyph, a title, a message
/// and the page's own content, scrolling when it doesn't fit (large Dynamic
/// Type sizes).
struct StackStepPage<Content: View>: View {

    let systemImage: String
    var tint: Color = .accentColor
    let title: String
    let message: String
    @ViewBuilder let content: () -> Content

    @ScaledMetric(relativeTo: .title) private var glyphSize: CGFloat = 64

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                VStack(spacing: 12) {
                    Image(systemName: systemImage)
                        .font(.system(size: glyphSize * 0.45, weight: .semibold))
                        .foregroundStyle(tint)
                        .frame(width: glyphSize, height: glyphSize)
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
                        .fixedSize(horizontal: false, vertical: true)
                }

                content()
            }
            .frame(maxWidth: 560)
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
    }
}
