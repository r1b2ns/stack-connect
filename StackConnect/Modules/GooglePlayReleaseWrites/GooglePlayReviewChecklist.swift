import Foundation

/// The Review Checklist of a release write (prototype screen 6): what Google
/// will validate, item by item, before the user publishes. Pure, built from
/// the pending write and cached context.
///
/// "Also in this edit" (store listing and screenshot changes batched with the
/// release) is deferred with the Store block (plan R3): one commit per action.
struct GooglePlayReviewChecklist: Equatable {

    enum State: Equatable {
        case satisfied
        case warning
    }

    struct Item: Equatable, Identifiable {
        let id: String
        let title: String
        var detail: String? = nil
        let value: String
        let state: State
    }

    /// "Release · Production".
    let title: String
    let items: [Item]

    var hasWarnings: Bool {
        items.contains { $0.state == .warning }
    }

    /// - Parameters:
    ///   - listingLanguages: store listing languages (cached), the languages
    ///     release notes are expected in; empty when unknown.
    ///   - liveVersionCode: highest version code live on the target track,
    ///     for new and promoted releases.
    static func make(
        write: GooglePlayPendingWrite,
        listingLanguages: [String],
        liveVersionCode: Int64?
    ) -> GooglePlayReviewChecklist {
        let content = Content(write: write)
        var items: [Item] = []

        items.append(Item(
            id: "bundle",
            title: String(localized: "App bundle selected"),
            value: content.versionCodes.isEmpty ? String(localized: "None") : content.versionCodes.joined(separator: ", "),
            state: content.versionCodes.isEmpty ? .warning : .satisfied
        ))

        let name = content.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        items.append(Item(
            id: "name",
            title: String(localized: "Release name"),
            value: name.isEmpty ? String(localized: "Not set") : GooglePlayReleaseNaming.shortName(name: name, versionCodes: content.versionCodes),
            state: name.isEmpty ? .warning : .satisfied
        ))

        let written = Set(content.notes.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.map(\.language))
        let expected = listingLanguages.isEmpty ? content.notes.map(\.language) : listingLanguages
        let missing = expected.filter { !written.contains($0) }
        let tooLong = content.notes.contains { $0.text.count > GooglePlayReleaseDetailUiState.releaseNotesLimit }
        var notesDetail: String?
        if tooLong {
            notesDetail = String(localized: "Longer than \(GooglePlayReleaseDetailUiState.releaseNotesLimit) characters in some languages")
        } else if !missing.isEmpty {
            let names = missing.map { GooglePlayLanguage.displayName(for: $0) }.formatted(.list(type: .and))
            notesDetail = String(localized: "Missing in \(names)", comment: "Google Play checklist. Argument: list of languages.")
        }
        items.append(Item(
            id: "notes",
            title: String(localized: "Release notes"),
            detail: notesDetail,
            value: expected.isEmpty
                ? String(localized: "None")
                : String(localized: "\(expected.count - missing.count) of \(expected.count)", comment: "Release notes languages filled, of expected."),
            state: (missing.isEmpty && !tooLong && !expected.isEmpty) ? .satisfied : .warning
        ))

        if let rollout = content.rollout {
            items.append(Item(id: "rollout", title: rollout.title, value: rollout.value, state: .satisfied))
        }

        if write.change.addsRelease, let highest = content.versionCodes.compactMap(Int64.init).max() {
            if let live = liveVersionCode {
                let higher = highest > live
                items.append(Item(
                    id: "versionCode",
                    title: String(localized: "Version code is higher than live"),
                    value: "\(highest) \(higher ? ">" : "≤") \(live)",
                    state: higher ? .satisfied : .warning
                ))
            } else {
                items.append(Item(
                    id: "versionCode",
                    title: String(localized: "Version code is higher than live"),
                    value: String(localized: "Nothing live"),
                    state: .satisfied
                ))
            }
        }

        return GooglePlayReviewChecklist(
            title: String(localized: "Release · \(write.trackKind.displayName)", comment: "Checklist section. Argument: track name."),
            items: items
        )
    }

    /// The highest version code served on `track` (in progress, halted or
    /// completed), leaving out the release itself.
    static func liveVersionCode(on track: GooglePlayTrackModel?, excluding versionCodes: [String] = []) -> Int64? {
        let excluded = Set(versionCodes)
        return track?.releases
            .filter { [.inProgress, .halted, .completed].contains($0.status) }
            .flatMap(\.versionCodes)
            .filter { !excluded.contains($0) }
            .compactMap(Int64.init)
            .max()
    }

    // MARK: - Content after the change

    /// What the release looks like once the change is applied.
    private struct Content {
        var versionCodes: [String]
        var name: String?
        var notes: [GooglePlayLocalizedTextModel]
        var rollout: (title: String, value: String)?

        init(write: GooglePlayPendingWrite) {
            let source = write.release
            versionCodes = write.change.versionCodes
            name = source?.name
            notes = source?.releaseNotes ?? []
            switch write.change {
            case .setRollout(_, let fraction):
                rollout = (String(localized: "Staged rollout"), GooglePlayPendingWrite.percent(fraction))
            case .complete:
                rollout = (String(localized: "Rollout"), String(localized: "All users"))
            case .updateMetadata(_, let update):
                name = update.name ?? name
                notes = update.releaseNotes ?? notes
            case .create(let release):
                name = release.name
                notes = release.releaseNotes
                rollout = Self.rollout(release.status)
            case .promote(_, _, let status, let newName, let newNotes, _):
                name = newName ?? name
                notes = newNotes ?? notes
                rollout = Self.rollout(status)
            case .halt, .resume:
                break
            }
        }

        private static func rollout(_ status: GooglePlayNewReleaseStatus) -> (String, String) {
            switch status {
            case .draft:                     return (String(localized: "Rollout"), String(localized: "Draft"))
            case .inProgress(let fraction):  return (String(localized: "Staged rollout"), GooglePlayPendingWrite.percent(fraction))
            case .completed:                 return (String(localized: "Rollout"), String(localized: "All users"))
            }
        }
    }
}
