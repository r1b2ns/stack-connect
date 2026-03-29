import SwiftUI

// MARK: - Factory

struct AppHistoryViewFactory {
    static func build(appId: String, account: AccountModel) -> some View {
        AppHistoryEntryView(appId: appId, account: account)
    }
}

// MARK: - Entry

private struct AppHistoryEntryView: View {
    let appId: String
    let account: AccountModel

    @StateObject private var viewModel: AppHistoryViewModel

    init(appId: String, account: AccountModel) {
        self.appId = appId
        self.account = account
        _viewModel = StateObject(wrappedValue: AppHistoryViewModel(appId: appId, account: account))
    }

    var body: some View {
        AppHistoryView(viewModel: viewModel)
    }
}

// MARK: - View

struct AppHistoryView<ViewModel: AppHistoryViewModelProtocol>: View {

    @ObservedObject var viewModel: ViewModel

    var body: some View {
        buildContent()
            .navigationTitle(String(localized: "History"))
            .navigationBarTitleDisplayMode(.inline)
            .task { await viewModel.load() }
            .refreshable { await viewModel.load() }
    }

    // MARK: - Content

    @ViewBuilder
    private func buildContent() -> some View {
        if viewModel.uiState.isLoading && viewModel.uiState.groups.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.uiState.groups.isEmpty {
            buildEmptyState()
        } else {
            buildList()
        }
    }

    @ViewBuilder
    private func buildEmptyState() -> some View {
        if let error = viewModel.uiState.error {
            ContentUnavailableView {
                Label(String(localized: "Error"), systemImage: "exclamationmark.triangle")
            } description: {
                Text(error)
            }
        } else {
            ContentUnavailableView {
                Label(String(localized: "No History"), systemImage: "clock")
            } description: {
                Text("No version history found for this app.")
            }
        }
    }

    private func buildList() -> some View {
        List {
            ForEach(viewModel.uiState.groups) { group in
                Section {
                    ForEach(group.entries) { entry in
                        buildEntryRow(entry)
                    }
                } header: {
                    buildSectionHeader(group)
                }
            }
        }
    }

    // MARK: - Section Header

    private func buildSectionHeader(_ group: AppHistoryGroup) -> some View {
        HStack(spacing: 8) {
            Text("v\(group.versionString)")
                .font(.subheadline)
                .fontWeight(.semibold)

            if let platform = group.platform {
                Text(platform.displayName)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.15))
                    .clipShape(Capsule())
            }
        }
    }

    // MARK: - Entry Row

    private func buildEntryRow(_ entry: AppHistoryEntry) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(stateColor(entry.statusColor))
                .frame(width: 10, height: 10)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 4) {
                Text(entry.activity)
                    .font(.body)
                    .fontWeight(.medium)

                HStack(spacing: 8) {
                    if let actor = entry.actorName {
                        Label(actor, systemImage: "person.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let date = entry.date {
                        Label(formatDate(date), systemImage: "calendar")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Text(entry.status)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(stateColor(entry.statusColor))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(stateColor(entry.statusColor).opacity(0.12))
                    .clipShape(Capsule())
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Helpers

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM dd, yyyy, HH:mm"
        return formatter.string(from: date)
    }

    private func stateColor(_ color: AppStoreStateColor) -> Color {
        switch color {
        case .green:  return .green
        case .orange: return .orange
        case .red:    return .red
        case .gray:   return .gray
        case .blue:   return .blue
        case .yellow: return .yellow
        }
    }
}
