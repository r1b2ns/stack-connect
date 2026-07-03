import SwiftUI

// MARK: - Build Picker Sheet

/// Reusable sheet for picking a build to run some action on. Standalone and
/// closure-driven so any flow can present it: the caller supplies the list of
/// builds and handles `onSelect` (e.g. add to a beta group in TestFlight, or
/// attach to an App Store version in Version Detail).
///
/// - `title`: navigation title, tailored to the action ("Add Build",
///   "Select Build", …).
/// - `assignedBuildIds`: builds to mark as already-in-use / current (shown with
///   a checkmark). Callers that want to hide them should filter `builds` instead.
/// - `isBusy`: an action is in flight — disables the list and shows a spinner.
struct BuildPickerSheet: View {

    let title: String
    let appId: String
    let account: AccountModel
    let assignedBuildIds: Set<String>
    let builds: [BuildModel]
    let isLoading: Bool
    var isBusy: Bool = false
    let onSelect: (BuildModel) -> Void
    let onCancel: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var path = NavigationPath()

    private var buildsByPlatform: [PlatformBuildGroup] {
        let sorted = builds.sorted { ($0.uploadedDate ?? .distantPast) > ($1.uploadedDate ?? .distantPast) }
        let dict = Dictionary(grouping: sorted) { $0.platform ?? "" }
        return dict
            .map { PlatformBuildGroup(platform: $0.key, builds: $0.value) }
            .sorted { BuildPlatform.sortOrder($0.platform) < BuildPlatform.sortOrder($1.platform) }
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if builds.isEmpty {
                    ContentUnavailableView {
                        Label(String(localized: "No Builds"), systemImage: "hammer")
                    } description: {
                        Text(String(localized: "No builds are available."))
                    }
                } else {
                    buildList
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) {
                        dismiss()
                        onCancel()
                    }
                }
            }
            .navigationDestination(for: BuildPickerPlatformRoute.self) { route in
                AvailableBuildsForPlatformViewFactory.build(
                    appId: appId,
                    platform: route.platform,
                    account: account,
                    assignedBuildIds: assignedBuildIds,
                    isAdding: isBusy,
                    onSelect: onSelect
                )
            }
            .overlay {
                if isBusy {
                    ZStack {
                        Color.black.opacity(0.1)
                        ProgressView()
                            .scaleEffect(1.2)
                    }
                    .ignoresSafeArea()
                }
            }
        }
    }

    private var buildList: some View {
        List {
            ForEach(buildsByPlatform, id: \.platform) { group in
                Section {
                    ForEach(group.builds.prefix(5)) { build in
                        Button {
                            onSelect(build)
                        } label: {
                            buildRow(build)
                        }
                    }

                    if group.builds.count > 5 {
                        Button {
                            path.append(BuildPickerPlatformRoute(platform: group.platform))
                        } label: {
                            HStack {
                                Text(String(localized: "See More"))
                                    .font(.body)
                                    .fontWeight(.medium)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .foregroundStyle(.tint)
                    }
                } header: {
                    Label(
                        BuildPlatform.label(for: group.platform),
                        systemImage: BuildPlatform.icon(for: group.platform)
                    )
                }
            }
        }
        .disabled(isBusy)
    }

    private func buildRow(_ build: BuildModel) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(build.displayVersion)
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)

                if let date = build.uploadedDate {
                    Text(formatDate(date))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if assignedBuildIds.contains(build.id) {
                Image(systemName: "checkmark")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.tint)
            }

            buildStateLabel(build.processingState)
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func buildStateLabel(_ state: String?) -> some View {
        let (text, color): (String, Color) = {
            switch state {
            case "VALID":      return (String(localized: "Ready"), .green)
            case "PROCESSING": return (String(localized: "Processing"), .orange)
            case "FAILED":     return (String(localized: "Failed"), .red)
            case "INVALID":    return (String(localized: "Invalid"), .red)
            default:           return ("–", .gray)
            }
        }()

        return Text(text)
            .font(.caption)
            .fontWeight(.medium)
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }
}

private struct BuildPickerPlatformRoute: Hashable {
    let platform: String
}
