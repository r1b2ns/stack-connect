import SwiftUI

// MARK: - Factory

@MainActor
struct NetworkAuditRetentionViewFactory {
    static func build() -> some View {
        NetworkAuditRetentionEntry()
    }
}

// MARK: - Entry

private struct NetworkAuditRetentionEntry: View {
    @StateObject private var viewModel = NetworkAuditRetentionViewModel()

    var body: some View {
        NetworkAuditRetentionView(viewModel: viewModel)
    }
}

// MARK: - View

/// Retention period, what is recorded, storage stats, where the log lives,
/// and "Delete entire log now".
struct NetworkAuditRetentionView<ViewModel: NetworkAuditRetentionViewModelProtocol>: View {

    @ObservedObject var viewModel: ViewModel
    @State private var showDeleteAllConfirmation = false

    var body: some View {
        Form {
            buildRetentionSection()
            buildRecordingSection()
            buildStorageSection()
            buildLocationSection()
            buildDeleteSection()
        }
        .navigationTitle(String(localized: "Retention", comment: "Network audit: retention screen title (short)."))
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
        .toast(message: $viewModel.uiState.toast, duration: 1.6)
        .alert(
            String(localized: "Delete Entire Log?", comment: "Network audit: Delete All confirmation title."),
            isPresented: $showDeleteAllConfirmation
        ) {
            Button(String(localized: "Cancel"), role: .cancel) {}
            Button(String(localized: "Delete", comment: "Network audit: confirms deleting the whole log."), role: .destructive) {
                Task { await viewModel.deleteAll() }
            }
        } message: {
            Text(String(localized: "Events are deleted permanently. New ones keep being recorded.", comment: "Network audit: Delete All confirmation message."))
        }
        .trackScreen(.networkAuditRetention)
    }

    // MARK: - Sections

    @ViewBuilder
    private func buildRetentionSection() -> some View {
        let shown = viewModel.uiState.pendingReduction?.retention ?? viewModel.uiState.retention
        Section {
            ForEach(NetworkAuditRetention.allCases) { retention in
                StackChoiceRow(
                    title: String(localized: "\(retention.days) days", comment: "Network audit: a retention option."),
                    isSelected: retention == shown
                ) {
                    Task { await viewModel.select(retention) }
                }
            }
        } header: {
            Text(String(localized: "Keep Records For", comment: "Network audit: retention section header."))
        } footer: {
            Text(String(localized: "Events older than the chosen period are deleted automatically, every day and whenever the app opens.", comment: "Network audit: retention section footer."))
        }

        if let pending = viewModel.uiState.pendingReduction {
            Section {
                buildPendingReduction(pending)
                    .networkAuditClearRow(top: 0, bottom: 0)
            }
            .listSectionSpacing(14)
        }
    }

    private func buildPendingReduction(_ pending: NetworkAuditPendingReduction) -> some View {
        StackWarningCard(
            systemImage: "exclamationmark.triangle.fill",
            text: String(
                localized: "Reducing to \(pending.retention.days) days deletes \(pending.eventCount) events recorded before \(pending.cutoff.formatted(date: .abbreviated, time: .omitted)) now. This can't be undone.",
                comment: "Network audit: confirmation of a shorter retention. Arguments: days, event count, cutoff date."
            )
        ) {
            HStack(spacing: 8) {
                Button {
                    viewModel.cancelReduction()
                } label: {
                    Text(String(localized: "Cancel"))
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14)
                        .frame(minHeight: 36)
                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.orange.opacity(0.45), lineWidth: 1))
                }
                .buttonStyle(.plain)
                Button {
                    Task { await viewModel.confirmReduction() }
                } label: {
                    Text(String(localized: "Reduce and Delete", comment: "Network audit: confirms a shorter retention and purges."))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 36)
                        .background(NetworkAuditPalette.destructive, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func buildRecordingSection() -> some View {
        Section {
            Toggle(isOn: Binding(get: { viewModel.uiState.recordsFullBodies }, set: { viewModel.setRecordsFullBodies($0) })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "Full Bodies", comment: "Network audit: setting that records request and response bodies."))
                    Text(String(localized: "Records the content sent and received, besides the headers", comment: "Network audit: subtitle of the Full Bodies setting."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            LabeledContent(String(localized: "Network Requests", comment: "Network audit: always recorded item."), value: String(localized: "Always", comment: "Network audit: an item that is always recorded."))
            LabeledContent(String(localized: "Telemetry and Crashes", comment: "Network audit: always recorded item."), value: String(localized: "Always", comment: "Network audit: an item that is always recorded."))
            LabeledContent(String(localized: "Imported Files", comment: "Network audit: always recorded item."), value: String(localized: "Always", comment: "Network audit: an item that is always recorded."))
        } header: {
            Text(String(localized: "What Is Recorded", comment: "Network audit: recording section header."))
        } footer: {
            Text(String(localized: "Recording can't be paused: the audit only counts if it shows everything. Without bodies, each event keeps method, address, headers, status and size.", comment: "Network audit: recording section footer."))
        }
    }

    private func buildStorageSection() -> some View {
        let stats = viewModel.uiState.stats
        return Section(String(localized: "Storage", comment: "Network audit: storage section header.")) {
            LabeledContent(String(localized: "Events", comment: "Network audit: stored event count."), value: "\(stats.eventCount)")
            LabeledContent(String(localized: "Space Used", comment: "Network audit: disk space used by the log."), value: NetworkAuditFormatting.bytes(stats.byteCount))
            LabeledContent(
                String(localized: "Oldest", comment: "Network audit: date of the oldest stored event."),
                value: stats.oldestDate?.formatted(date: .abbreviated, time: .omitted) ?? "—"
            )
        }
    }

    private func buildLocationSection() -> some View {
        Section {
            buildLocationRow("iphone", String(localized: "Only on this device. Never sent to StackConnect or anyone else.", comment: "Network audit: where the log is stored."))
            buildLocationRow("icloud.slash", String(localized: "Excluded from iCloud backups and never synced between devices.", comment: "Network audit: the log is not backed up."))
            buildLocationRow("lock.fill", String(localized: "Encrypted by iOS, and tokens are encrypted again with a key kept in this device's Keychain.", comment: "Network audit: how the log is encrypted."))
        } header: {
            Text(String(localized: "Where It Is Stored", comment: "Network audit: storage location section header."))
        }
    }

    private func buildLocationRow(_ systemImage: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 22)
                .accessibilityHidden(true)
            Text(text)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
        .listRowSeparator(.hidden)
        .padding(.vertical, 2)
    }

    private func buildDeleteSection() -> some View {
        Section {
            Button {
                showDeleteAllConfirmation = true
            } label: {
                Text(String(localized: "Delete Entire Log Now", comment: "Network audit: deletes every stored event."))
                    .foregroundStyle(NetworkAuditPalette.destructive)
                    .frame(maxWidth: .infinity)
            }
        } footer: {
            Text(String(localized: "Events are deleted permanently. New ones keep being recorded.", comment: "Network audit: Delete All confirmation message."))
        }
    }
}
