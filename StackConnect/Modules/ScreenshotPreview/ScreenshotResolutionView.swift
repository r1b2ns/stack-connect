import SwiftUI

// MARK: - Factory

@MainActor
struct ScreenshotResolutionViewFactory {
    static func build(device: ScreenshotDeviceType, sets: [ScreenshotSetModel], account: AccountModel, appStoreState: AppStoreState?) -> some View {
        ScreenshotResolutionView(device: device, sets: sets, account: account, appStoreState: appStoreState)
    }
}

// MARK: - View

struct ScreenshotResolutionView: View {

    let device: ScreenshotDeviceType
    let sets: [ScreenshotSetModel]
    let account: AccountModel
    let appStoreState: AppStoreState?
    @EnvironmentObject private var homeCoordinator: HomeCoordinator

    var body: some View {
        buildContent()
            .navigationTitle(device.title)
            .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func buildContent() -> some View {
        if sets.isEmpty {
            ContentUnavailableView {
                Label(String(localized: "No Screenshots"), systemImage: "photo.on.rectangle.angled")
            } description: {
                Text("No screenshots available for \(device.title).")
            }
        } else {
            List(sets) { set in
                Button {
                    homeCoordinator.navigateToScreenshotGrid(screenshots: set.screenshots, account: account, appStoreState: appStoreState)
                } label: {
                    HStack(spacing: 12) {
                        if let first = set.screenshots.first,
                           let urlStr = first.imageUrl,
                           let url = URL(string: urlStr) {
                            AsyncImage(url: url) { phase in
                                switch phase {
                                case .success(let image):
                                    image
                                        .resizable()
                                        .scaledToFill()
                                case .failure:
                                    screenshotPlaceholder
                                case .empty:
                                    ProgressView()
                                        .frame(width: 44, height: 44)
                                @unknown default:
                                    screenshotPlaceholder
                                }
                            }
                            .frame(width: 44, height: 44)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        } else {
                            screenshotPlaceholder
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(set.displayName)
                                .font(.body)
                                .foregroundStyle(.primary)

                            Text("\(set.screenshots.count) screenshots")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .foregroundStyle(.primary)
            }
            
        }
    }

    private var screenshotPlaceholder: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(Color.gray.opacity(0.15))
            .frame(width: 44, height: 44)
            .overlay {
                Image(systemName: "photo")
                    .foregroundStyle(.secondary)
            }
    }
}
