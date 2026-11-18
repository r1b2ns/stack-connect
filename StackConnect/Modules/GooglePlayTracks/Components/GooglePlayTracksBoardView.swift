import SwiftUI

// MARK: - Board Order

/// Column order of the tracks board: the path a build takes, from internal
/// testing to production (custom closed tracks sit with closed testing).
enum GooglePlayTracksBoard {

    static func columns(_ tracks: [GooglePlayTrackModel]) -> [GooglePlayTrackModel] {
        tracks.enumerated()
            .sorted { lhs, rhs in
                let l = rank(lhs.element.kind), r = rank(rhs.element.kind)
                return l == r ? lhs.offset < rhs.offset : l < r
            }
            .map(\.element)
    }

    static func rank(_ kind: GooglePlayTrackKind) -> Int {
        switch kind {
        case .internalTesting: return 0
        case .closedTesting:   return 1
        case .custom:          return 2
        case .openTesting:     return 3
        case .production:      return 4
        }
    }
}

/// A release picked on the board.
struct GooglePlayBoardSelection: Hashable {
    let track: String
    let index: Int
}

// MARK: - Board View

/// Regular-width Tracks & Releases: one column per track (Internal → Closed →
/// Open → Production), and the selected release below with its staged rollout
/// control. Writes go through the same `GooglePlayReleaseWriteViewModel` path
/// (confirmation, checklist, commit) as the iPhone screens.
struct GooglePlayTracksBoardView<Writes: GooglePlayReleaseWriteViewModelProtocol>: View {

    let tracks: [GooglePlayTrackModel]
    let app: GooglePlayAppItem
    let account: AccountModel
    @ObservedObject var writes: Writes
    let onOpenRelease: (GooglePlayReleaseModel, String) -> Void

    @State private var selection: GooglePlayBoardSelection?

    private var columns: [GooglePlayTrackModel] {
        GooglePlayTracksBoard.columns(tracks)
    }

    private var selected: (track: GooglePlayTrackModel, release: GooglePlayReleaseModel)? {
        guard let selection,
              let track = tracks.first(where: { $0.track == selection.track }),
              track.releases.indices.contains(selection.index) else { return nil }
        return (track, track.releases[selection.index])
    }

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 20) {
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: 16) {
                        ForEach(columns) { track in
                            buildColumn(track)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 4)
                }

                if let selected {
                    GooglePlayReleasePanel(
                        track: selected.track,
                        release: selected.release,
                        writes: writes,
                        onOpen: { onOpenRelease(selected.release, selected.track.track) }
                    )
                    .id(selected.release.releaseKey(track: selected.track.track))
                    .padding(.horizontal, 20)
                }
            }
            .padding(.vertical, 16)
        }
        .background(Color(.systemGroupedBackground))
        .onChange(of: tracks) {
            // A write may have moved the selected release away.
            if selected == nil { selection = nil }
        }
    }

    // MARK: - Column

    private func buildColumn(_ track: GooglePlayTrackModel) -> some View {
        StackCard(title: track.kind.displayName, systemImage: track.kind.icon) {
            VStack(alignment: .leading, spacing: 8) {
                if track.releases.isEmpty {
                    Text("No releases")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                ForEach(Array(track.releases.enumerated()), id: \.offset) { index, release in
                    buildReleaseCard(release, isSelected: selection == .init(track: track.track, index: index)) {
                        selection = .init(track: track.track, index: index)
                    }
                    .contextMenu {
                        Button {
                            onOpenRelease(release, track.track)
                        } label: {
                            Label(String(localized: "Open Release"), systemImage: "arrow.up.right.square")
                        }
                        if writes.canPerform(.edit), GooglePlayReleaseActions.supportsStagedRollout(track.kind) {
                            Button {
                                writes.openRollout(release: release, track: track.track)
                            } label: {
                                Label(String(localized: "Staged Rollout"), systemImage: "slider.horizontal.3")
                            }
                        }
                    }
                }
            }
        } accessory: {
            if writes.canPerform(.add) {
                Button {
                    writes.openNewRelease(track: track.track)
                } label: {
                    Image(systemName: "plus.circle.fill")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(Text("New release on \(track.kind.displayName)"))
            }
        }
        .frame(width: 280)
    }

    private func buildReleaseCard(_ release: GooglePlayReleaseModel, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(release.displayName)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    StackCapsuleBadge(title: release.status.displayName, color: release.status.color)
                }
                if !release.versionCodes.isEmpty {
                    Text(release.versionCodes.joined(separator: ", "))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if let fraction = release.rolloutFraction {
                    GooglePlayRolloutLabel(fraction: fraction, status: release.status)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? Color.accentColor.opacity(0.12) : Color(.tertiarySystemGroupedBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1.5)
            )
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Release Panel

/// The selected release under the board: what it is, and its staged rollout
/// (slider + steps, Halt / Resume) when the track supports one. Saving asks
/// for the same confirmation as the Staged Rollout sheet.
private struct GooglePlayReleasePanel<Writes: GooglePlayReleaseWriteViewModelProtocol>: View {

    let track: GooglePlayTrackModel
    let release: GooglePlayReleaseModel
    @ObservedObject var writes: Writes
    let onOpen: () -> Void

    @State private var form: GooglePlayRolloutForm

    init(track: GooglePlayTrackModel, release: GooglePlayReleaseModel, writes: Writes, onOpen: @escaping () -> Void) {
        self.track = track
        self.release = release
        self.writes = writes
        self.onOpen = onOpen
        _form = State(initialValue: GooglePlayRolloutForm(target: GooglePlayRolloutTarget(track: track.track, release: release)))
    }

    private var target: GooglePlayRolloutTarget {
        GooglePlayRolloutTarget(track: track.track, release: release)
    }

    private var canEditRollout: Bool {
        writes.canPerform(.edit)
            && GooglePlayReleaseActions.supportsStagedRollout(track.kind)
            && release.status != .completed
    }

    var body: some View {
        StackCard(title: "\(track.kind.displayName) · \(release.displayName)", systemImage: "shippingbox") {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    StackCapsuleBadge(title: release.status.displayName, color: release.status.color)
                    if !release.versionCodes.isEmpty {
                        Text("Version codes: \(release.versionCodes.joined(separator: ", "))")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                if let fraction = release.rolloutFraction {
                    GooglePlayRolloutLabel(fraction: fraction, status: release.status)
                }

                if canEditRollout {
                    buildRolloutControl()
                }
            }
        } accessory: {
            Button(String(localized: "Open Release")) { onOpen() }
                .buttonStyle(.borderless)
        }
    }

    private func buildRolloutControl() -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
            HStack {
                Text("Staged rollout")
                    .font(.headline)
                Spacer()
                Text(GooglePlayRolloutSheet<Writes>.percentText(form.percent))
                    .font(.headline.monospacedDigit())
            }
            Slider(
                value: Binding(
                    get: { Double(form.percent) },
                    set: { form.method = .percentage; form.percent = Int($0.rounded()) }
                ),
                in: 1...99,
                step: 1
            )
            .tint(.teal)
            .accessibilityLabel(Text("Rollout percentage"))
            .accessibilityValue(Text(GooglePlayRolloutSheet<Writes>.percentText(form.percent)))

            HStack(spacing: 6) {
                ForEach(GooglePlayRolloutForm.steps, id: \.self) { step in
                    StackStepChip(title: GooglePlayRolloutSheet<Writes>.percentText(step), isSelected: form.percent == step) {
                        form.method = .percentage
                        form.percent = step
                    }
                }
            }

            HStack(spacing: 12) {
                if release.status == .inProgress {
                    Button(String(localized: "Halt Rollout")) {
                        request(.halt(versionCodes: release.versionCodes))
                    }
                    .buttonStyle(.bordered)
                    .tint(.orange)
                } else if release.status == .halted {
                    Button(String(localized: "Resume Rollout")) {
                        request(.resume(versionCodes: release.versionCodes))
                    }
                    .buttonStyle(.bordered)
                }

                Spacer()

                Button(String(localized: "Release to All Users")) {
                    request(.complete(versionCodes: release.versionCodes))
                }
                .buttonStyle(.bordered)

                Button(String(localized: "Update Rollout", comment: "Tracks board: saves the chosen staged rollout percentage.")) {
                    var percentage = form
                    percentage.method = .percentage
                    if let change = percentage.change(for: target) {
                        request(change)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(form.change(for: target) == nil || form.method != .percentage)
            }
            .disabled(writes.uiState.isWriting)
        }
    }

    private func request(_ change: GooglePlayReleaseChange) {
        writes.request(GooglePlayPendingWrite(track: track.track, change: change, releaseTitle: release.shortName, release: release))
    }
}
