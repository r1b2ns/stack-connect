import SwiftUI

/// What the Staged Rollout sheet edits: one release of one track.
struct GooglePlayRolloutTarget: Identifiable, Hashable {
    let track: String
    let release: GooglePlayReleaseModel

    var id: GooglePlayReleaseKey { release.releaseKey(track: track) }
    var trackKind: GooglePlayTrackKind { GooglePlayTrackKind(track: track) }
}

/// The Staged Rollout sheet's choices, kept apart from the view so the
/// resulting change is unit-testable.
struct GooglePlayRolloutForm: Equatable {

    enum Method: Hashable {
        case allUsers
        case percentage
    }

    var method: Method
    /// 1...99.
    var percent: Int

    static let steps = [1, 5, 10, 20, 50, 99]

    /// Starts from the running rollout, or the next step for a draft.
    init(target: GooglePlayRolloutTarget, increasing: Bool = false) {
        let current = target.release.rolloutFraction.map { Int(($0 * 100).rounded()) }
        method = GooglePlayReleaseActions.supportsStagedRollout(target.trackKind) ? .percentage : .allUsers
        if let current, increasing {
            percent = Self.steps.first { $0 > current } ?? 99
        } else {
            percent = min(max(current ?? 10, 1), 99)
        }
    }

    /// `nil` when saving would change nothing.
    func change(for target: GooglePlayRolloutTarget) -> GooglePlayReleaseChange? {
        let codes = target.release.versionCodes
        switch method {
        case .allUsers:
            return .complete(versionCodes: codes)
        case .percentage:
            let fraction = Double(percent) / 100
            if let current = target.release.userFraction, target.release.status == .inProgress,
               abs(current - fraction) < 0.0001 {
                return nil
            }
            return .setRollout(versionCodes: codes, userFraction: fraction)
        }
    }
}

/// Staged Rollout sheet (prototype screen 4): release method, percentage
/// (slider + steps), and the running rollout's status with Halt / Resume.
struct GooglePlayRolloutSheet<Writes: GooglePlayReleaseWriteViewModelProtocol>: View {

    let target: GooglePlayRolloutTarget
    @ObservedObject var writes: Writes
    @State private var form: GooglePlayRolloutForm
    @Environment(\.dismiss) private var dismiss

    init(target: GooglePlayRolloutTarget, increasing: Bool, writes: Writes) {
        self.target = target
        self.writes = writes
        _form = State(initialValue: GooglePlayRolloutForm(target: target, increasing: increasing))
    }

    private var release: GooglePlayReleaseModel { target.release }
    private var supportsStaged: Bool { GooglePlayReleaseActions.supportsStagedRollout(target.trackKind) }

    var body: some View {
        NavigationStack {
            Form {
                buildMethodSection()
                if form.method == .percentage {
                    buildPercentageSection()
                }
                buildStatusSection()
                Section {
                } footer: {
                    Text(writes.uiState.rolloutEditFooter)
                }
            }
            .navigationTitle(String(localized: "Staged Rollout"))
            .navigationBarTitleDisplayMode(.inline)
            .trackScreen(.googlePlayRollout)
            .googlePlayReleaseWrites(writes, inSheet: true)
            .googlePlayReviewChecklistDestination(writes)
            .onChange(of: writes.uiState.revision) { dismiss() }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    StackTrackedButton(String(localized: "Cancel"), button: .cancel, on: .googlePlayRollout) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    StackTrackedButton(String(localized: "Save"), button: .save, on: .googlePlayRollout) { save() }
                        .fontWeight(.semibold)
                        .disabled(form.change(for: target) == nil)
                }
            }
        }
    }

    // MARK: - Sections

    private func buildMethodSection() -> some View {
        Section {
            StackChoiceRow(
                title: String(localized: "Release to all users immediately"),
                isSelected: form.method == .allUsers
            ) { form.method = .allUsers }
            if supportsStaged {
                StackChoiceRow(
                    title: String(localized: "Release to a percentage of users"),
                    isSelected: form.method == .percentage
                ) { form.method = .percentage }
            }
        } header: {
            Text("Release Method")
        } footer: {
            if !supportsStaged {
                Text("Staged rollout is available for production and open testing.")
            }
        }
    }

    private func buildPercentageSection() -> some View {
        Section {
            LabeledContent(String(localized: "Users receiving update")) {
                Text(Self.percentText(form.percent))
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                    .monospacedDigit()
            }
            VStack(alignment: .leading, spacing: 10) {
                Text("Drag to change, or pick a step")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Slider(
                    value: Binding(get: { Double(form.percent) }, set: { form.percent = Int($0.rounded()) }),
                    in: 1...99,
                    step: 1
                )
                .tint(.teal)
                .accessibilityLabel(Text("Rollout percentage"))
                .accessibilityValue(Text(Self.percentText(form.percent)))
                HStack(spacing: 6) {
                    ForEach(GooglePlayRolloutForm.steps, id: \.self) { step in
                        StackStepChip(title: Self.percentText(step), isSelected: form.percent == step) {
                            form.percent = step
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        } header: {
            Text("Rollout Percentage")
        } footer: {
            Text("Unlike App Store phased release, Google Play has no fixed 7-day schedule: you choose each step, from 1% to 99%.")
        }
    }

    @ViewBuilder
    private func buildStatusSection() -> some View {
        if release.status == .inProgress || release.status == .halted {
            Section {
                LabeledContent(String(localized: "Status")) {
                    StackCapsuleBadge(title: release.status.displayName, color: release.status.color)
                }
                if let fraction = release.rolloutFraction {
                    LabeledContent(String(localized: "Currently live for"),
                                   value: String(localized: "\(GooglePlayPendingWrite.percent(fraction)) of users"))
                }
                if release.status == .inProgress {
                    StackTrackedButton(String(localized: "Halt Rollout"), button: .haltRollout, on: .googlePlayRollout) {
                        request(.halt(versionCodes: release.versionCodes))
                    }
                    .foregroundStyle(.orange)
                } else {
                    StackTrackedButton(String(localized: "Resume Rollout"), button: .resumeRollout, on: .googlePlayRollout) {
                        request(.resume(versionCodes: release.versionCodes))
                    }
                }
            } header: {
                Text("Rollout Status")
            } footer: {
                Text("Halting stops new users from getting this release. Users who already updated keep it. You can resume later.")
            }
        }
    }

    static func percentText(_ percent: Int) -> String {
        (Double(percent) / 100).formatted(.percent.precision(.fractionLength(0)))
    }

    // MARK: - Actions

    private func save() {
        guard let change = form.change(for: target) else { return }
        request(change)
    }

    /// Asks for confirmation over the sheet; the sheet closes once the write
    /// succeeded (`revision` changes).
    private func request(_ change: GooglePlayReleaseChange) {
        writes.request(GooglePlayPendingWrite(track: target.track, change: change, releaseTitle: release.shortName, release: release))
    }
}
