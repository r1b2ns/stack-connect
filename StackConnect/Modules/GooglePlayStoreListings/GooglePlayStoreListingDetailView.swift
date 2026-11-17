import SwiftUI

// MARK: - Factory

@MainActor
struct GooglePlayStoreListingDetailViewFactory {
    static func build(listing: GooglePlayStoreListingModel, isDefaultLanguage: Bool) -> some View {
        GooglePlayStoreListingDetailView(listing: listing, isDefaultLanguage: isDefaultLanguage)
    }
}

// MARK: - View

/// One localized store listing, read-only. Pure display of an already loaded
/// model, so it has no ViewModel.
struct GooglePlayStoreListingDetailView: View {

    let listing: GooglePlayStoreListingModel
    let isDefaultLanguage: Bool

    var body: some View {
        List {
            buildLanguageSection()
            buildTextSection(String(localized: "Title"), text: listing.title)
            buildTextSection(String(localized: "Short Description"), text: listing.shortDescription)
            buildTextSection(String(localized: "Full Description"), text: listing.fullDescription)
            buildVideoSection()
        }
        .navigationTitle(GooglePlayLanguage.displayName(for: listing.language))
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Sections

    private func buildLanguageSection() -> some View {
        Section {
            LabeledContent(String(localized: "Language")) {
                HStack(spacing: 6) {
                    Text(listing.language)
                    if isDefaultLanguage {
                        StackCapsuleBadge(title: String(localized: "Default"), color: .green)
                    }
                }
            }
        }
    }

    private func buildTextSection(_ title: String, text: String?) -> some View {
        Section {
            if let text, !text.isEmpty {
                HStack(alignment: .top) {
                    Text(text)
                        .font(.body)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    CopyButton(text: text)
                }
            } else {
                Text("Not set")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text(title)
        }
    }

    @ViewBuilder
    private func buildVideoSection() -> some View {
        Section {
            if let video = listing.video, let url = ExternalLinkURL.web(video) {
                Link(destination: url) {
                    Label(video, systemImage: "play.rectangle.fill")
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            } else if let video = listing.video, !video.isEmpty {
                // Not a web link (`ExternalLinkURL`): shown, never opened.
                Text(video)
                    .textSelection(.enabled)
            } else {
                Text("Not set")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Promo Video")
        }
    }
}
