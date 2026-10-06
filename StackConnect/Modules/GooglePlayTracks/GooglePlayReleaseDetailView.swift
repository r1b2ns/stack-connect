import SwiftUI

// MARK: - Factory

@MainActor
struct GooglePlayReleaseDetailViewFactory {
    static func build(release: GooglePlayReleaseModel, track: GooglePlayTrackKind) -> some View {
        GooglePlayReleaseDetailView(release: release, track: track)
    }
}

// MARK: - View

/// One release of a Google Play track, read-only: status, version codes,
/// rollout, in-app update priority and the release notes per language. Pure
/// display of an already loaded model, so it has no ViewModel.
struct GooglePlayReleaseDetailView: View {

    let release: GooglePlayReleaseModel
    let track: GooglePlayTrackKind

    var body: some View {
        List {
            buildReleaseSection()
            buildReleaseNotesSections()
        }
        .navigationTitle(release.displayName)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Release

    private func buildReleaseSection() -> some View {
        Section {
            LabeledContent(String(localized: "Track"), value: track.displayName)

            LabeledContent(String(localized: "Status")) {
                StackCapsuleBadge(title: release.status.displayName, color: release.status.color)
            }

            LabeledContent(String(localized: "Version Codes")) {
                Text(release.versionCodes.isEmpty ? "–" : release.versionCodes.joined(separator: ", "))
                    .textSelection(.enabled)
            }

            if let fraction = release.rolloutFraction {
                GooglePlayRolloutLabel(fraction: fraction, status: release.status)
                    .padding(.vertical, 2)
            }

            if let priority = release.inAppUpdatePriority {
                LabeledContent(String(localized: "In-App Update Priority"), value: "\(priority)")
            }
        } header: {
            Text("Release")
        }
    }

    // MARK: - Release Notes

    @ViewBuilder
    private func buildReleaseNotesSections() -> some View {
        if release.releaseNotes.isEmpty {
            Section {
                Text("No release notes")
                    .foregroundStyle(.secondary)
            } header: {
                Text("Release Notes")
            }
        } else {
            ForEach(release.releaseNotes, id: \.language) { note in
                Section {
                    HStack(alignment: .top) {
                        Text(note.text)
                            .font(.body)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        CopyButton(text: note.text)
                    }
                } header: {
                    Text("Release Notes – \(GooglePlayLanguage.displayName(for: note.language))")
                }
            }
        }
    }
}
