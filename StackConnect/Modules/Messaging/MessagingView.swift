import SwiftUI
import APIProviderFirebase

// MARK: - Factory

@MainActor
struct MessagingViewFactory {
    static func build(project: FirebaseProjectModel, account: AccountModel) -> some View {
        MessagingEntry(project: project, account: account)
    }
}

// MARK: - Entry

private struct MessagingEntry: View {
    let project: FirebaseProjectModel
    let account: AccountModel

    @StateObject private var viewModel: MessagingViewModel

    init(project: FirebaseProjectModel, account: AccountModel) {
        self.project = project
        self.account = account
        _viewModel = StateObject(wrappedValue: MessagingViewModel(project: project, account: account))
    }

    var body: some View {
        MessagingView(viewModel: viewModel)
    }
}

// MARK: - View

struct MessagingView<ViewModel: MessagingViewModelProtocol>: View {

    @ObservedObject var viewModel: ViewModel

    var body: some View {
        buildContent()
            .navigationTitle(String(localized: "Messaging"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { buildToolbar() }
            .sheet(isPresented: $viewModel.uiState.showNewCampaign) {
                NewCampaignSheet(
                    availableApps: viewModel.uiState.availableApps,
                    isLoadingApps: viewModel.uiState.isLoadingApps,
                    isSending: viewModel.uiState.isSending,
                    onLoadApps: { Task { await viewModel.loadApps() } },
                    onSend: { draft in Task { await viewModel.sendCampaign(draft) } },
                    onCancel: { viewModel.uiState.showNewCampaign = false }
                )
            }
            .toast(message: $viewModel.uiState.toastMessage)
    }

    // MARK: - Content

    @ViewBuilder
    private func buildContent() -> some View {
        VStack(spacing: 0) {
            buildTabPicker()

            switch viewModel.uiState.selectedTab {
            case .campaigns:
                buildCampaigns()
                    .task { await viewModel.loadCampaigns() }
            case .reports:
                buildReports()
                    .task { await viewModel.loadReports() }
            }
        }
    }

    private func buildTabPicker() -> some View {
        Picker(String(localized: "Section"), selection: $viewModel.uiState.selectedTab) {
            ForEach(MessagingTab.allCases) { tab in
                Text(tab.rawValue).tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: - Campaigns

    @ViewBuilder
    private func buildCampaigns() -> some View {
        if viewModel.uiState.isLoadingCampaigns && viewModel.uiState.campaigns.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.uiState.campaigns.isEmpty {
            ContentUnavailableView {
                Label(String(localized: "No Campaigns"), systemImage: "bell.slash")
            } description: {
                Text("Campaigns sent from StackConnect will appear here. Firebase does not provide a public API to list console-created campaigns.")
            } actions: {
                Button(String(localized: "New Campaign")) {
                    viewModel.uiState.showNewCampaign = true
                }
                .buttonStyle(.borderedProminent)
            }
        } else {
            buildCampaignList()
        }
    }

    private func buildCampaignList() -> some View {
        List {
            ForEach(viewModel.uiState.campaigns) { campaign in
                buildCampaignRow(campaign)
            }
            .onDelete { indexSet in
                let toDelete = indexSet.map { viewModel.uiState.campaigns[$0] }
                Task {
                    for c in toDelete { await viewModel.deleteCampaign(c) }
                }
            }
        }
    }

    private func buildCampaignRow(_ campaign: CampaignRecord) -> some View {
        HStack(spacing: 12) {
            Image(systemName: statusIcon(campaign.status))
                .foregroundStyle(statusColor(campaign.status))
                .font(.title3)

            VStack(alignment: .leading, spacing: 3) {
                Text(campaign.title)
                    .font(.body)
                    .fontWeight(.medium)

                Text(campaign.body)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                HStack(spacing: 6) {
                    Label(campaign.targetType.rawValue, systemImage: targetIcon(campaign.targetType))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)

                    Text("·")
                        .font(.caption2)
                        .foregroundStyle(.quaternary)

                    Text(campaign.targetValue)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)

                    if campaign.sentCount > 1 || campaign.failedCount > 0 {
                        Text("·")
                            .font(.caption2)
                            .foregroundStyle(.quaternary)

                        Text("\(campaign.sentCount) sent")
                            .font(.caption2)
                            .foregroundStyle(.green)

                        if campaign.failedCount > 0 {
                            Text("\(campaign.failedCount) failed")
                                .font(.caption2)
                                .foregroundStyle(.red)
                        }
                    }
                }

                Text(campaign.sentAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(.quaternary)
            }

            Spacer()
        }
        .padding(.vertical, 2)
    }

    private func statusIcon(_ status: CampaignRecord.Status) -> String {
        switch status {
        case .sent: return "checkmark.circle.fill"
        case .partiallyFailed: return "exclamationmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        }
    }

    private func statusColor(_ status: CampaignRecord.Status) -> Color {
        switch status {
        case .sent: return .green
        case .partiallyFailed: return .orange
        case .failed: return .red
        }
    }

    private func targetIcon(_ target: CampaignTarget) -> String {
        switch target {
        case .topic: return "number"
        case .condition: return "line.3.horizontal.decrease"
        case .userSegment: return "person.2.fill"
        }
    }

    // MARK: - Reports

    @ViewBuilder
    private func buildReports() -> some View {
        if viewModel.uiState.isLoadingReports {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = viewModel.uiState.reportError {
            buildReportError(error)
        } else if viewModel.uiState.reports.isEmpty {
            ContentUnavailableView {
                Label(String(localized: "No Reports"), systemImage: "chart.bar")
            } description: {
                Text("Delivery reports for Android apps will appear here.")
            }
        } else {
            buildReportList()
        }
    }

    private func buildReportError(_ message: String) -> some View {
        ContentUnavailableView {
            Label(String(localized: "Unavailable"), systemImage: "chart.bar.xaxis")
        } description: {
            Text(message)
        } actions: {
            if let urlString = viewModel.uiState.reportApiActivationURL,
               let url = URL(string: urlString) {
                Link(destination: url) {
                    Label(String(localized: "Enable API"), systemImage: "arrow.up.forward.app")
                }
                .buttonStyle(.borderedProminent)
            }

            Button(String(localized: "Retry")) {
                Task { await viewModel.loadReports() }
            }
        }
    }

    private func buildReportList() -> some View {
        List {
            ForEach(viewModel.uiState.reports) { row in
                buildReportRow(row)
            }
        }
    }

    private func buildReportRow(_ row: DeliveryReportRow) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(row.date)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Spacer()

                if let label = row.analyticsLabel, !label.isEmpty {
                    Text(label)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.12))
                        .clipShape(Capsule())
                }
            }

            HStack(spacing: 16) {
                buildReportStat(
                    title: String(localized: "Accepted"),
                    value: row.messagesAccepted.formatted(),
                    color: .blue
                )
                buildReportStat(
                    title: String(localized: "Delivered"),
                    value: String(format: "%.0f%%", row.deliveredPercent),
                    color: .green
                )
                buildReportStat(
                    title: String(localized: "Collapsed"),
                    value: String(format: "%.0f%%", row.collapsedPercent),
                    color: .orange
                )
                buildReportStat(
                    title: String(localized: "Dropped"),
                    value: String(format: "%.0f%%", row.droppedPercent),
                    color: .red
                )
            }
        }
        .padding(.vertical, 4)
    }

    private func buildReportStat(title: String, value: String, color: Color) -> some View {
        VStack(spacing: 1) {
            Text(value)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(color)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private func buildToolbar() -> some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            if viewModel.uiState.selectedTab == .campaigns {
                Button {
                    viewModel.uiState.showNewCampaign = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
    }
}

// MARK: - New Campaign Sheet

struct NewCampaignSheet: View {

    let availableApps: [SelectableApp]
    let isLoadingApps: Bool
    let isSending: Bool
    let onLoadApps: () -> Void
    let onSend: (CampaignDraft) -> Void
    let onCancel: () -> Void

    @State private var draft = CampaignDraft()
    @State private var newDataKey = ""
    @State private var newDataValue = ""

    var body: some View {
        NavigationStack {
            List {
                buildNotificationSection()
                buildTargetSection()
                buildAppsSection()
                buildOptionsSection()
                buildCustomDataSection()
            }
            .navigationTitle(String(localized: "New Campaign"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) { onCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSending {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Button(String(localized: "Send")) {
                            onSend(draft)
                        }
                        .disabled(!draft.isValid)
                        .fontWeight(.semibold)
                    }
                }
            }
            .task { onLoadApps() }
        }
    }

    // MARK: - Notification

    private func buildNotificationSection() -> some View {
        Section {
            LabeledContent(String(localized: "Title")) {
                TextField(String(localized: "Notification title"), text: $draft.title)
                    .multilineTextAlignment(.trailing)
            }

            LabeledContent(String(localized: "Body")) {
                TextField(String(localized: "Notification body"), text: $draft.body)
                    .multilineTextAlignment(.trailing)
            }

            LabeledContent(String(localized: "Image URL")) {
                TextField(String(localized: "https://..."), text: $draft.imageURL)
                    .multilineTextAlignment(.trailing)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
            }
        } header: {
            Text("Notification")
        }
    }

    // MARK: - Target

    private func buildTargetSection() -> some View {
        Section {
            Picker(String(localized: "Target Type"), selection: $draft.targetType) {
                ForEach(CampaignTarget.allCases) { target in
                    Text(target.rawValue).tag(target)
                }
            }

            switch draft.targetType {
            case .topic:
                LabeledContent(String(localized: "Topic")) {
                    TextField(String(localized: "news"), text: $draft.topic)
                        .multilineTextAlignment(.trailing)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
            case .condition:
                LabeledContent(String(localized: "Condition")) {
                    TextField("'dogs' in topics", text: $draft.condition)
                        .multilineTextAlignment(.trailing)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .font(.system(.caption, design: .monospaced))
                }
            case .userSegment:
                EmptyView()
            }
        } header: {
            Text("Target")
        } footer: {
            switch draft.targetType {
            case .topic:
                Text("Send to all devices subscribed to this topic.")
            case .condition:
                Text("Boolean expression combining topics (max 5).")
            case .userSegment:
                Text("Select one or more apps below. A message will be sent to each selected app's topic.")
            }
        }
    }

    // MARK: - Apps Selection

    @ViewBuilder
    private func buildAppsSection() -> some View {
        if draft.targetType == .userSegment {
            Section {
                if isLoadingApps {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                } else if availableApps.isEmpty {
                    Text(String(localized: "No apps found"))
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                } else {
                    ForEach(availableApps) { app in
                        buildAppToggleRow(app)
                    }
                }
            } header: {
                HStack {
                    Text("Apps")
                    Spacer()
                    if !availableApps.isEmpty {
                        let count = draft.selectedApps.count
                        Text("\(count) selected")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } footer: {
                Text("Each app receives a message via its topic (bundle ID / package name). Devices must be subscribed to the corresponding topic for delivery.")
            }
        }
    }

    private func buildAppToggleRow(_ app: SelectableApp) -> some View {
        let isSelected = draft.selectedApps.contains(app.appId)

        return Button {
            if isSelected {
                draft.selectedApps.remove(app.appId)
            } else {
                draft.selectedApps.insert(app.appId)
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: app.platform.iconName)
                    .font(.body)
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(app.platform.color)
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                VStack(alignment: .leading, spacing: 1) {
                    Text(app.displayName)
                        .font(.body)
                        .foregroundStyle(.primary)

                    HStack(spacing: 4) {
                        Text(app.platformIdentifier)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)

                        if isSelected {
                            Text("·")
                                .font(.caption2)
                                .foregroundStyle(.quaternary)
                            Text("topic: \(app.topicName)")
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.blue.opacity(0.7))
                                .lineLimit(1)
                        }
                    }
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.blue : Color.secondary.opacity(0.4))
                    .font(.title3)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Options

    private func buildOptionsSection() -> some View {
        Section {
            LabeledContent(String(localized: "Analytics Label")) {
                TextField(String(localized: "Optional"), text: $draft.analyticsLabel)
                    .multilineTextAlignment(.trailing)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            }
        } header: {
            Text("Options")
        } footer: {
            Text("Attach a label to track this campaign in Firebase Analytics reports.")
        }
    }

    // MARK: - Custom Data

    private func buildCustomDataSection() -> some View {
        Section {
            ForEach(Array(draft.customData.enumerated()), id: \.offset) { _, pair in
                HStack {
                    Text(pair.key)
                        .font(.caption)
                        .fontWeight(.medium)
                    Spacer()
                    Text(pair.value)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .onDelete { indexSet in
                draft.customData.remove(atOffsets: indexSet)
            }

            HStack(spacing: 8) {
                TextField(String(localized: "Key"), text: $newDataKey)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .font(.caption)

                TextField(String(localized: "Value"), text: $newDataValue)
                    .autocorrectionDisabled()
                    .font(.caption)

                Button {
                    guard !newDataKey.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                    draft.customData.append((key: newDataKey, value: newDataValue))
                    newDataKey = ""
                    newDataValue = ""
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(.blue)
                }
                .disabled(newDataKey.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        } header: {
            Text("Custom Data")
        } footer: {
            Text("Key-value pairs delivered as a data payload to the app.")
        }
    }
}

// MARK: - Platform Helpers

private extension FirebaseAppPlatform {
    var color: Color {
        switch self {
        case .ios: return .blue
        case .android: return .green
        case .web: return .orange
        case .unknown: return .gray
        }
    }
}
