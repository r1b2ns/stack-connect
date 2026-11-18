import SwiftUI

// MARK: - Regular Content

/// Regular-width Version Detail: a header, the phased release hero card and the
/// rest as a grid of cards (two columns when there is room, one otherwise).
/// Same view model and actions as the compact List; navigation and permission
/// checks stay in `VersionDetailView` and come in as closures.
struct VersionDetailRegularContent<ViewModel: VersionDetailViewModelProtocol>: View {

    @ObservedObject var viewModel: ViewModel
    let canEditMetadata: Bool
    let onBuild: () -> Void
    let onScreenshots: () -> Void
    let onAppReviewInfo: () -> Void
    let onReleaseOptions: () -> Void
    let onPhasedRelease: () -> Void

    private let columns = [GridItem(.adaptive(minimum: 340), spacing: 16, alignment: .top)]

    private var showsPhasedHero: Bool {
        guard viewModel.uiState.version.appStoreState == .readyForSale,
              let state = viewModel.uiState.phasedRelease?.state else { return false }
        return state == .active || state == .paused || state == .complete
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                buildHeader()

                if showsPhasedHero, let phased = viewModel.uiState.phasedRelease {
                    PhasedReleaseHeroCard(phased: phased, onManage: onPhasedRelease)
                }

                LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                    buildBuildCard()
                    buildScreenshotsCard()
                    buildReleaseCard()
                    buildWhatsNewCard()
                    buildStoreTextCard()
                    buildMetadataCard()
                }
            }
            .padding(20)
        }
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - Header

    private func buildHeader() -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            if let platform = viewModel.uiState.version.platform {
                Label(platform.displayName, systemImage: platform.icon)
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            Text(viewModel.uiState.version.versionString ?? "–")
                .font(.largeTitle.bold())
            Spacer()
            if let state = viewModel.uiState.version.appStoreState {
                StackStatusLine(color: state.color.swiftUIColor, text: state.displayName)
                    .font(.headline)
            }
        }
    }

    // MARK: - Cards

    private func buildBuildCard() -> some View {
        StackCard(title: String(localized: "Build"), systemImage: "hammer") {
            StackTrackedCardButton(.build, on: .versionDetail, action: onBuild) {
                HStack {
                    if let build = viewModel.uiState.currentBuild {
                        Text(build.version ?? "–")
                            .font(.body.monospacedDigit())
                    } else {
                        Text("No build selected")
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private func buildScreenshotsCard() -> some View {
        StackCard(title: String(localized: "Preview and Screenshots"), systemImage: "photo.on.rectangle.angled") {
            StackTrackedCardButton(.screenshots, on: .versionDetail, action: onScreenshots) {
                HStack {
                    Text(String(localized: "Manage", comment: "Version Detail (iPad): opens the screenshots of the version."))
                        .foregroundStyle(.tint)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private func buildReleaseCard() -> some View {
        StackCard(title: String(localized: "Release"), systemImage: "arrow.up.circle") {
            VStack(alignment: .leading, spacing: 8) {
                buildDetailRow(
                    .releaseOptions,
                    title: String(localized: "App Store Version Release"),
                    value: viewModel.uiState.releaseTypeSubtitle,
                    action: onReleaseOptions
                )
                Divider()
                buildDetailRow(
                    .phasedRelease,
                    title: String(localized: "Phased Release"),
                    value: viewModel.uiState.phasedReleaseSubtitle,
                    action: onPhasedRelease
                )
                Divider()
                buildDetailRow(
                    .appReviewInfo,
                    title: String(localized: "App Review Information"),
                    value: nil,
                    action: onAppReviewInfo
                )
            }
        }
    }

    private func buildWhatsNewCard() -> some View {
        StackCard(title: String(localized: "What's New"), systemImage: "sparkles") {
            buildTextPreview(viewModel.uiState.editWhatsNew, lineLimit: 8)
        } accessory: {
            buildEditButton(.whatsNew, analyticsButton: .whatsNew)
        }
    }

    private func buildStoreTextCard() -> some View {
        StackCard(title: String(localized: "Store Text", comment: "Version Detail (iPad): card with the promotional text and the description."), systemImage: "doc.text") {
            VStack(alignment: .leading, spacing: 8) {
                StackTrackedCardButton(.promotionalText, on: .versionDetail) { viewModel.requestField(.promotionalText) } label: {
                    buildPreviewRow(title: String(localized: "Promotional Text"), text: viewModel.uiState.editPromotionalText, lineLimit: 2)
                }
                Divider()
                StackTrackedCardButton(.appDescription, on: .versionDetail) { viewModel.requestField(.description) } label: {
                    buildPreviewRow(title: String(localized: "Description"), text: viewModel.uiState.editDescription, lineLimit: 3)
                }
            }
        }
    }

    private func buildMetadataCard() -> some View {
        StackCard(title: String(localized: "Metadata"), systemImage: "list.bullet.rectangle") {
            VStack(alignment: .leading, spacing: 10) {
                VersionMetadataFields(viewModel: viewModel, canEdit: canEditMetadata)
            }
            .textFieldStyle(.roundedBorder)
        }
    }

    // MARK: - Pieces

    private func buildDetailRow(
        _ analyticsButton: AnalyticsButton,
        title: String,
        value: String?,
        action: @escaping () -> Void
    ) -> some View {
        StackTrackedCardButton(analyticsButton, on: .versionDetail, action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .foregroundStyle(.primary)
                    if let value {
                        Text(value)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func buildPreviewRow(title: String, text: String, lineLimit: Int) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .foregroundStyle(.primary)
                buildTextPreview(text, lineLimit: lineLimit)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private func buildTextPreview(_ text: String, lineLimit: Int) -> some View {
        if text.isEmpty {
            Text(String(localized: "Empty", comment: "Version Detail (iPad): a store text with no content yet."))
                .font(.subheadline)
                .foregroundStyle(.tertiary)
        } else {
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(lineLimit)
                .multilineTextAlignment(.leading)
        }
    }

    private func buildEditButton(_ field: VersionDetailLocalizableField, analyticsButton: AnalyticsButton) -> some View {
        StackTrackedButton(
            canEditMetadata ? String(localized: "Edit") : String(localized: "View"),
            button: analyticsButton,
            on: .versionDetail
        ) {
            viewModel.requestField(field)
        }
        .buttonStyle(.borderless)
    }
}

// MARK: - Phased Release Hero

/// The phased release front and center: status, the 7-day timeline with each
/// day's share of users, and where the rollout stands today.
struct PhasedReleaseHeroCard: View {

    let phased: PhasedReleaseModel
    let onManage: () -> Void

    private var steps: [PhasedReleaseSchedule.Step] {
        PhasedReleaseSchedule.steps(for: phased)
    }

    private var tint: Color {
        phased.state == .paused ? .orange : .teal
    }

    var body: some View {
        StackCard(title: String(localized: "Phased Release"), systemImage: "chart.bar.doc.horizontal.fill") {
            VStack(alignment: .leading, spacing: 14) {
                buildSummary()
                buildTimeline()
                if let startDate = phased.startDate {
                    Text(String(localized: "Started \(startDate.formatted(date: .abbreviated, time: .shortened))", comment: "Phased release card: when the rollout started."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        } accessory: {
            // Same event as the Phased Release row (compact List and card).
            StackTrackedButton(
                String(localized: "Manage", comment: "Phased release card: opens the phased release options."),
                button: .phasedRelease,
                on: .versionDetail
            ) {
                onManage()
            }
            .buttonStyle(.borderless)
        }
    }

    private func buildSummary() -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if let state = phased.state {
                StackCapsuleBadge(title: state.displayName, color: tint)
            }
            if let day = phased.displayDayNumber {
                Text(String(localized: "Day \(day) of 7"))
                    .font(.title3.weight(.semibold))
                Text(String(
                    localized: "\(PhasedReleaseSchedule.percentage(forDay: day))% of users on automatic updates",
                    comment: "Phased release card: share of users that get the update today."
                ))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
        }
    }

    private func buildTimeline() -> some View {
        HStack(alignment: .top, spacing: 6) {
            ForEach(steps) { step in
                VStack(spacing: 6) {
                    Capsule()
                        .fill(fill(for: step.progress))
                        .frame(height: step.progress == .current ? 10 : 6)
                        .frame(height: 10)
                    Text(String(localized: "Day \(step.day)", comment: "Phased release timeline: day of the 7-day rollout."))
                        .font(.caption2)
                        .foregroundStyle(step.progress == .upcoming ? .tertiary : .secondary)
                    Text("\(step.percentage)%")
                        .font(.caption.weight(step.progress == .current ? .bold : .regular))
                        .foregroundStyle(step.progress == .upcoming ? .secondary : .primary)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func fill(for progress: PhasedReleaseSchedule.Step.Progress) -> Color {
        switch progress {
        case .done:     return tint.opacity(0.55)
        case .current:  return tint
        case .upcoming: return Color.gray.opacity(0.25)
        }
    }
}

// MARK: - Metadata Fields

/// Keywords, URLs, version and copyright fields with copy buttons, plus the
/// save button when editable. Shared by the compact List section (each child
/// is a row) and the regular-width Metadata card.
struct VersionMetadataFields<ViewModel: VersionDetailViewModelProtocol>: View {

    @ObservedObject var viewModel: ViewModel
    let canEdit: Bool

    var body: some View {
        HStack {
            TextField(String(localized: "Keywords"), text: $viewModel.uiState.editKeywords)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .disabled(!canEdit)
            CopyButton(text: viewModel.uiState.editKeywords)
        }

        HStack {
            TextField(String(localized: "Support URL"), text: $viewModel.uiState.editSupportUrl)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .disabled(!canEdit)
            CopyButton(text: viewModel.uiState.editSupportUrl)
        }

        HStack {
            TextField(String(localized: "Marketing URL"), text: $viewModel.uiState.editMarketingUrl)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .disabled(!canEdit)
            CopyButton(text: viewModel.uiState.editMarketingUrl)
        }

        HStack {
            TextField(String(localized: "Version"), text: $viewModel.uiState.editVersion)
                .textInputAutocapitalization(.never)
                .keyboardType(.numbersAndPunctuation)
                .disabled(!canEdit)
            CopyButton(text: viewModel.uiState.editVersion)
        }

        HStack {
            TextField(String(localized: "Copyright"), text: $viewModel.uiState.editCopyright)
                .disabled(!canEdit)
            CopyButton(text: viewModel.uiState.editCopyright)
        }

        if let error = viewModel.uiState.groupedFieldsError {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .font(.caption)
        }

        if canEdit {
            Button {
                Task { await viewModel.saveGroupedFields() }
            } label: {
                HStack {
                    Spacer()
                    if viewModel.uiState.isSavingGroupedFields {
                        ProgressView()
                    } else {
                        Text("Save")
                            .fontWeight(.medium)
                    }
                    Spacer()
                }
            }
            .disabled(viewModel.uiState.isSavingGroupedFields)
            .foregroundStyle(.accent)
        }
    }
}
