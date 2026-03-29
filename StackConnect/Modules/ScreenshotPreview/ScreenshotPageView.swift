import SwiftUI

// MARK: - Factory

struct ScreenshotPageViewFactory {
    static func build(screenshots: [ScreenshotModel]) -> some View {
        ScreenshotPageView(screenshots: screenshots)
    }
}

// MARK: - View

struct ScreenshotPageView: View {

    let screenshots: [ScreenshotModel]
    @State private var currentIndex = 0

    var body: some View {
        TabView(selection: $currentIndex) {
            ForEach(Array(screenshots.enumerated()), id: \.element.id) { index, screenshot in
                buildScreenshotPage(screenshot)
                    .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .automatic))
        .navigationTitle("\(currentIndex + 1) / \(screenshots.count)")
        .navigationBarTitleDisplayMode(.inline)
        .background(Color.black)
        .ignoresSafeArea(.container, edges: .bottom)
    }

    private func buildScreenshotPage(_ screenshot: ScreenshotModel) -> some View {
        Group {
            if let urlStr = screenshot.imageUrl,
               let url = URL(string: urlStr) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                    case .failure:
                        buildPlaceholder()
                    case .empty:
                        ProgressView()
                            .tint(.white)
                    @unknown default:
                        buildPlaceholder()
                    }
                }
            } else {
                buildPlaceholder()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func buildPlaceholder() -> some View {
        VStack(spacing: 12) {
            Image(systemName: "photo")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("Image unavailable")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}
