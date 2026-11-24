import SwiftUI

// MARK: - Factory

@MainActor
struct NetworkAuditViewFactory {
    static func build() -> some View {
        NetworkAuditEntry()
    }
}

// MARK: - Entry

private struct NetworkAuditEntry: View {
    @StateObject private var coordinator = NetworkAuditCoordinator()
    @StateObject private var viewModel = NetworkAuditViewModel()

    var body: some View {
        NetworkAuditView(viewModel: viewModel)
            .environmentObject(coordinator)
    }
}

// MARK: - View

/// Settings › Privacy › Audit: everything the app sent and received, kept
/// only on this device. Pushed on the Home stack (`HomeRoute.networkAudit`).
///
/// Regular width with room for two columns (iPad, where the split view gives
/// the Audit the whole width, and Mac): the list (~400pt) and the selected
/// event side by side, the first event selected. Otherwise the event detail
/// is pushed.
struct NetworkAuditView<ViewModel: NetworkAuditViewModelProtocol>: View {

    /// Width of the list column next to the detail (prototype: 400pt).
    static var listColumnWidth: CGFloat { 400 }

    @ObservedObject var viewModel: ViewModel
    @EnvironmentObject private var coordinator: NetworkAuditCoordinator
    @EnvironmentObject private var homeCoordinator: HomeCoordinator
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        buildLayout()
            .background(Color(.systemGroupedBackground))
            .navigationTitle(String(localized: "Audit", comment: "Network audit: screen title."))
            .navigationBarTitleDisplayMode(.large)
            .searchable(
                text: Binding(get: { viewModel.uiState.searchText }, set: { viewModel.updateSearch($0) }),
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: String(localized: "Search host or path", comment: "Network audit: search field prompt.")
            )
            .toolbar { buildToolbar() }
            .onAppear { Task { await viewModel.load() } }
            .toast(message: $viewModel.uiState.toast, duration: 1.6)
            .sheet(item: $coordinator.sheet) { sheet in
                buildSheet(sheet)
                    .stackFormSheet()
            }
            .trackScreen(.networkAudit)
    }

    // MARK: - Layout

    @ViewBuilder
    private func buildLayout() -> some View {
        if horizontalSizeClass == .regular {
            GeometryReader { proxy in
                if proxy.size.width >= Self.listColumnWidth + 420 {
                    buildTwoColumns()
                } else {
                    buildList(isTwoColumns: false)
                }
            }
        } else {
            buildList(isTwoColumns: false)
        }
    }

    private func buildTwoColumns() -> some View {
        HStack(spacing: 0) {
            buildList(isTwoColumns: true)
                .frame(width: Self.listColumnWidth)
            Divider()
            buildDetailColumn()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear { selectFirstIfNeeded() }
        .onChange(of: viewModel.uiState.groups) { selectFirstIfNeeded() }
    }

    /// iPad: the detail column is never empty while there are events.
    private func selectFirstIfNeeded() {
        let visible = viewModel.uiState.groups.flatMap(\.events)
        if let selection = coordinator.selection, visible.contains(where: { $0.id == selection.id }) { return }
        if let first = visible.first {
            coordinator.select(first)
        }
    }

    @ViewBuilder
    private func buildDetailColumn() -> some View {
        if let selection = coordinator.selection {
            NetworkAuditDetailViewFactory.build(summary: selection, isEmbedded: true)
                .id(selection.id)
        } else {
            ContentUnavailableView(
                String(localized: "No Event Selected", comment: "Network audit: placeholder of the detail column."),
                systemImage: "list.bullet.rectangle",
                description: Text(String(localized: "Choose an event to see what was sent and received.", comment: "Network audit: placeholder message of the detail column."))
            )
        }
    }

    // MARK: - List

    private func buildList(isTwoColumns: Bool) -> some View {
        List {
            Section {
                if !isTwoColumns {
                    buildBanner()
                        .networkAuditClearRow(top: 0, bottom: 7)
                }
                buildTiles(isTwoColumns: isTwoColumns)
                    .networkAuditClearRow(top: 7, bottom: 9)
                buildSegmentedControl()
                    .networkAuditClearRow(top: 9, bottom: 6)
                if viewModel.uiState.segment == .events {
                    StackFlowFilterChips(
                        items: NetworkAuditFilter.allCases,
                        selection: viewModel.uiState.filter,
                        title: \.title,
                        height: isTwoColumns ? 30 : 32,
                        onSelect: viewModel.selectFilter
                    )
                    .networkAuditClearRow(top: 6, bottom: 0)
                    buildCountRow()
                        .networkAuditClearRow(top: 4, bottom: 0)
                }
            }
            .listSectionSpacing(8)

            switch viewModel.uiState.segment {
            case .events:
                buildEventSections(isTwoColumns: isTwoColumns)
            case .destinations:
                buildDestinationsSection()
            }
        }
        .listStyle(.insetGrouped)
        .contentMargins(.top, 4, for: .scrollContent)
        .refreshable { await viewModel.load() }
    }

    private func buildBanner() -> some View {
        StackTrackedButton(.networkAuditRetention, on: .networkAudit) {
            homeCoordinator.navigateToNetworkAudit(.retention)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(NetworkAuditPalette.indigo, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "Stays on this device", comment: "Network audit banner title."))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(String(localized: "Kept for \(viewModel.uiState.retentionDays) days. Older events are deleted automatically.", comment: "Network audit banner message. Argument: retention in days."))
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func buildTiles(isTwoColumns: Bool) -> some View {
        let today = viewModel.uiState.today
        let columns = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]
        return LazyVGrid(columns: columns, spacing: 8) {
            buildTile(
                title: String(localized: "Requests Today", comment: "Network audit tile: requests made today."),
                value: "\(today.requestCount)",
                isCompact: isTwoColumns
            )
            if isTwoColumns {
                buildTile(
                    title: String(localized: "Sent · Received", comment: "Network audit tile (iPad): bytes sent and received today."),
                    value: "\(NetworkAuditFormatting.bytes(today.bytesSent)) · \(NetworkAuditFormatting.bytes(today.bytesReceived))",
                    isCompact: true
                )
            } else {
                buildTile(
                    title: String(localized: "Destinations", comment: "Network audit tile: distinct hosts contacted today."),
                    value: "\(today.destinationCount)"
                )
                buildTile(
                    title: String(localized: "Sent", comment: "Network audit tile: bytes sent today."),
                    value: NetworkAuditFormatting.bytes(today.bytesSent),
                    glyph: ("arrow.up", Color.accentColor)
                )
                buildTile(
                    title: String(localized: "Received", comment: "Network audit tile: bytes received today."),
                    value: NetworkAuditFormatting.bytes(today.bytesReceived),
                    glyph: ("arrow.down", NetworkAuditPalette.greenText)
                )
            }
        }
    }

    private func buildTile(title: String, value: String, glyph: (String, Color)? = nil, isCompact: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: isCompact ? 2 : 4) {
            HStack(spacing: 4) {
                if let glyph {
                    Image(systemName: glyph.0)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(glyph.1)
                        .accessibilityHidden(true)
                }
                Text(title)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .font(.system(size: isCompact ? 12 : 13))
            .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: isCompact ? 20 : 24, weight: .bold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, isCompact ? 12 : 14)
        .padding(.vertical, isCompact ? 10 : 12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func buildSegmentedControl() -> some View {
        Picker(
            String(localized: "View", comment: "Network audit: segmented control label (Events / Destinations)."),
            selection: Binding(get: { viewModel.uiState.segment }, set: { viewModel.selectSegment($0) })
        ) {
            ForEach(NetworkAuditSegment.allCases) { segment in
                Text(segment.title).tag(segment)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    private func buildCountRow() -> some View {
        HStack {
            Text(String(localized: "\(viewModel.uiState.visibleCount) events in this filter", comment: "Network audit: count of the events the filter shows."))
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer()
            StackTrackedButton(.networkAuditExport, on: .networkAudit) {
                presentBatchExport()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "square.and.arrow.up")
                    Text(String(localized: "Export", comment: "Network audit: opens the export sheet."))
                }
                .font(.system(size: 15, weight: .semibold))
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
            }
            .buttonStyle(.borderless)
            .disabled(viewModel.uiState.totalCount == 0)
        }
        .padding(.leading, 16)
        .padding(.trailing, 4)
    }

    @ViewBuilder
    private func buildEventSections(isTwoColumns: Bool) -> some View {
        if viewModel.uiState.groups.isEmpty, !viewModel.uiState.isLoading {
            Section {
                Text(String(localized: "No events for this filter.", comment: "Network audit: empty list."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .networkAuditClearRow(top: 24, bottom: 0)
            }
        }

        ForEach(viewModel.uiState.groups) { group in
            Section {
                ForEach(group.events) { summary in
                    buildEventRow(summary, isTwoColumns: isTwoColumns)
                }
            } header: {
                HStack {
                    Text(group.title)
                    Spacer()
                    Text(String(localized: "\(group.events.count) events", comment: "Network audit: count of a day's events."))
                }
                .font(.footnote)
            }
            .listSectionSpacing(20)
        }
    }

    private func buildEventRow(_ summary: NetworkAuditEventSummary, isTwoColumns: Bool) -> some View {
        let isSelected = isTwoColumns && coordinator.selection?.id == summary.id
        return Button {
            if isTwoColumns {
                coordinator.select(summary)
            } else {
                homeCoordinator.navigateToNetworkAudit(.event(summary))
            }
        } label: {
            NetworkAuditEventRow(summary: summary, isCompact: isTwoColumns, isSelected: isSelected)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets(top: 10, leading: isTwoColumns ? 12 : 14, bottom: 10, trailing: 14))
        .listRowBackground(isSelected ? Color.accentColor : Color(.secondarySystemGroupedBackground))
        .alignmentGuide(.listRowSeparatorLeading) { _ in isTwoColumns ? 0 : 40 }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func buildDestinationsSection() -> some View {
        Section {
            if viewModel.uiState.destinations.isEmpty {
                Text(String(localized: "No destinations yet.", comment: "Network audit: empty Destinations list."))
                    .foregroundStyle(.secondary)
            }
            ForEach(viewModel.uiState.destinations) { destination in
                NetworkAuditDestinationRow(destination: destination) {
                    viewModel.copyHost(destination.host)
                }
                .listRowInsets(EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14))
            }
        } header: {
            Text(String(localized: "Where the app connects · \(viewModel.uiState.retentionDays) days", comment: "Network audit: Destinations header. Argument: retention in days."))
                .font(.footnote)
        } footer: {
            Text(String(localized: "Every destination the app contacted shows up here, telemetry and remote configuration included. Nothing is left out.", comment: "Network audit: Destinations footer."))
        }
        .listSectionSpacing(20)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private func buildToolbar() -> some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            StackTrackedButton(.networkAuditExport, on: .networkAudit) {
                presentBatchExport()
            } label: {
                Label(String(localized: "Export Records", comment: "Network audit: batch export sheet title."), systemImage: "square.and.arrow.up")
            }
            .disabled(viewModel.uiState.totalCount == 0)

            StackTrackedButton(.networkAuditRetention, on: .networkAudit) {
                homeCoordinator.navigateToNetworkAudit(.retention)
            } label: {
                Label(String(localized: "Retention and Storage", comment: "Network audit: opens the retention settings."), systemImage: "gearshape")
            }
        }
    }

    // MARK: - Sheets

    private func presentBatchExport() {
        coordinator.presentBatchExport(filtered: viewModel.filteredSummaries, filterTitle: viewModel.uiState.filter.title)
    }

    @ViewBuilder
    private func buildSheet(_ sheet: NetworkAuditSheet) -> some View {
        switch sheet {
        case let .batchExport(filtered, filterTitle):
            NetworkAuditExportViewFactory.build(filteredSummaries: filtered, filterTitle: filterTitle)
        case .eventExport(let summary):
            NetworkAuditEventExportViewFactory.build(summary: summary)
        }
    }
}

// MARK: - Helpers

extension View {
    /// A List row drawn on the screen background (no card, no separator).
    func networkAuditClearRow(top: CGFloat, bottom: CGFloat, horizontal: CGFloat = 0) -> some View {
        listRowInsets(EdgeInsets(top: top, leading: horizontal, bottom: bottom, trailing: horizontal))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }
}
