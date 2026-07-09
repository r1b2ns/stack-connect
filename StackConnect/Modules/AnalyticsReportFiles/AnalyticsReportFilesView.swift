import SwiftUI

// MARK: - Factory

@MainActor
struct AnalyticsReportFilesViewFactory {
    static func build(appId: String, appName: String, report: AnalyticsCatalogReport, account: AccountModel) -> some View {
        AnalyticsReportFilesEntry(appId: appId, appName: appName, report: report, account: account)
    }
}

// MARK: - Entry

private struct AnalyticsReportFilesEntry: View {
    let appId: String
    let appName: String
    let report: AnalyticsCatalogReport
    let account: AccountModel

    @StateObject private var coordinator = AnalyticsReportFilesCoordinator()
    @StateObject private var viewModel: AnalyticsReportFilesViewModel

    init(appId: String, appName: String, report: AnalyticsCatalogReport, account: AccountModel) {
        self.appId = appId
        self.appName = appName
        self.report = report
        self.account = account
        _viewModel = StateObject(wrappedValue: AnalyticsReportFilesViewModel(
            appId: appId,
            appName: appName,
            report: report,
            account: account
        ))
    }

    var body: some View {
        AnalyticsReportFilesView(viewModel: viewModel)
            .environmentObject(coordinator)
    }
}

// MARK: - View

struct AnalyticsReportFilesView<ViewModel: AnalyticsReportFilesViewModelProtocol>: View {

    @ObservedObject var viewModel: ViewModel

    @State private var showDeleteConfirmation = false

    var body: some View {
        buildContent()
            .navigationTitle(viewModel.uiState.report.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { buildToolbar() }
            .task { await viewModel.load() }
            .sheet(item: $viewModel.uiState.shareItem) { item in
                AnalyticsShareSheet(activityItems: [item.url])
            }
            .alert(String(localized: "Delete Files"), isPresented: $showDeleteConfirmation) {
                Button(String(localized: "Cancel"), role: .cancel) {}
                Button(String(localized: "Delete"), role: .destructive) {
                    Task { await viewModel.delete() }
                }
            } message: {
                Text(String(localized: "This permanently removes the selected analytics files from this device. This action cannot be undone."))
            }
    }

    // MARK: - Content

    @ViewBuilder
    private func buildContent() -> some View {
        if viewModel.uiState.isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.uiState.isEmpty {
            buildEmptyState()
        } else {
            buildFileList()
        }
    }

    private func buildEmptyState() -> some View {
        ContentUnavailableView {
            Label(String(localized: "No Files"), systemImage: "tray")
        } description: {
            Text(String(localized: "No analytics files downloaded yet."))
        }
    }

    private func buildFileList() -> some View {
        List {
            ForEach(AnalyticsGranularity.allCases) { granularity in
                if let items = viewModel.uiState.itemsByGranularity[granularity], !items.isEmpty {
                    Section(granularity.displayName) {
                        ForEach(items) { item in
                            buildRow(item)
                        }
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if viewModel.uiState.isSelecting {
                buildBottomBar()
            }
        }
    }

    // MARK: - Row

    @ViewBuilder
    private func buildRow(_ item: AnalyticsFileItem) -> some View {
        let isSelected = viewModel.uiState.selectedIDs.contains(item.id)

        HStack(spacing: 12) {
            if viewModel.uiState.isSelecting {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .imageScale(.large)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(item.displayName)
                    .font(.body)

                HStack(spacing: 6) {
                    Text(analyticsFilesDateFormatter.string(from: item.downloadDate))
                    Text("•")
                    Text(ByteCountFormatter.string(fromByteCount: item.sizeBytes, countStyle: .file))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard viewModel.uiState.isSelecting else { return }
            viewModel.toggle(id: item.id)
        }
    }

    // MARK: - Bottom bar (selection mode)

    private func buildBottomBar() -> some View {
        HStack {
            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                Label(String(localized: "Delete"), systemImage: "trash")
            }
            .disabled(viewModel.uiState.selectedIDs.isEmpty)

            Spacer()

            Button {
                Task { await viewModel.share() }
            } label: {
                if viewModel.uiState.isProcessing {
                    ProgressView()
                } else {
                    Label(String(localized: "Share"), systemImage: "square.and.arrow.up")
                }
            }
            .disabled(viewModel.uiState.selectedIDs.isEmpty || viewModel.uiState.isProcessing)
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(.bar)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private func buildToolbar() -> some ToolbarContent {
        if !viewModel.uiState.isEmpty {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    viewModel.toggleSelecting()
                } label: {
                    Text(viewModel.uiState.isSelecting
                         ? String(localized: "Done")
                         : String(localized: "Select"))
                }
            }
        }
    }
}

// MARK: - Formatters
//
// File-level so they are shared and cached (a generic `View` type cannot hold
// static stored properties).

private let analyticsFilesDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US")
    formatter.dateStyle = .medium
    formatter.timeStyle = .none
    return formatter
}()

// MARK: - Share Sheet
//
// Non-deleting share sheet: the shared items are the persistent, per-instance
// analytics CSVs (or a temp zip of them) and must survive the share so they can
// be re-shared. (Relocated from AnalyticsReportDetailView.)

private struct AnalyticsShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
