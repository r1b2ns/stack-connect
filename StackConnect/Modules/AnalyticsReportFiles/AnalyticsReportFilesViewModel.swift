import Foundation

// MARK: - File Item

/// One downloaded analytics CSV on disk. `id` is the file path (stable, unique)
/// so it can back both `List` identity and the selection set.
struct AnalyticsFileItem: Identifiable, Hashable {
    let id: String
    let url: URL
    let granularity: AnalyticsGranularity?
    /// File basename without the `.csv` extension (the instance's period key).
    let displayName: String
    /// The file's modification date — i.e. when it was downloaded.
    let downloadDate: Date
    let sizeBytes: Int64
}

// MARK: - Protocol

@MainActor
protocol AnalyticsReportFilesViewModelProtocol: ObservableObject {
    var uiState: AnalyticsReportFilesUiState { get set }
    func load() async
    func toggleSelecting()
    func toggle(id: String)
    func selectAll()
    func clearSelection()
    func delete() async
    func share() async
}

// MARK: - UiState

struct AnalyticsReportFilesUiState {
    let appId: String
    let appName: String
    let report: AnalyticsCatalogReport
    let account: AccountModel

    /// Downloaded files grouped by granularity; each group is sorted newest-first.
    var itemsByGranularity: [AnalyticsGranularity: [AnalyticsFileItem]] = [:]

    var isLoading: Bool = true
    var isSelecting: Bool = false
    var selectedIDs: Set<String> = []
    var isProcessing: Bool = false
    var shareItem: ShareableFileURL?
    var errorMessage: String?

    /// Flat, section-ordered list of every file.
    var allItems: [AnalyticsFileItem] {
        AnalyticsGranularity.allCases.flatMap { itemsByGranularity[$0] ?? [] }
    }

    /// The files currently checked, preserving section order.
    var selectedItems: [AnalyticsFileItem] {
        allItems.filter { selectedIDs.contains($0.id) }
    }

    var isEmpty: Bool { allItems.isEmpty }
}

// MARK: - Implementation

@MainActor
final class AnalyticsReportFilesViewModel: AnalyticsReportFilesViewModelProtocol {

    @Published var uiState: AnalyticsReportFilesUiState

    // Not used today (no network), kept for signature parity with the sibling
    // detail VM so a real credentialed operation can be added without a breaking
    // init change.
    private let keychain: KeyStorable

    init(
        appId: String,
        appName: String,
        report: AnalyticsCatalogReport,
        account: AccountModel,
        keychain: KeyStorable = KeychainStorable.shared
    ) {
        self.uiState = AnalyticsReportFilesUiState(
            appId: appId,
            appName: appName,
            report: report,
            account: account
        )
        self.keychain = keychain
    }

    // MARK: - Load

    /// Scans the report's persistent directory, listing the `*.csv` files under
    /// each granularity subdir with their download date and size, sorted
    /// newest-first within each granularity.
    func load() async {
        uiState.isLoading = true
        defer { uiState.isLoading = false }

        let fm = FileManager.default
        let reportDir = AnalyticsReportFileStore.reportDirectory(
            appId: uiState.appId,
            category: uiState.report.category,
            apiName: uiState.report.apiName
        )

        var grouped: [AnalyticsGranularity: [AnalyticsFileItem]] = [:]
        for granularity in AnalyticsGranularity.allCases {
            let dir = reportDir.appendingPathComponent(granularity.rawValue, isDirectory: true)
            guard let entries = try? fm.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            var items: [AnalyticsFileItem] = []
            for url in entries where url.pathExtension.lowercased() == "csv" {
                let attrs = try? fm.attributesOfItem(atPath: url.path)
                let modDate = (attrs?[.modificationDate] as? Date) ?? .distantPast
                let size = (attrs?[.size] as? NSNumber)?.int64Value ?? 0
                items.append(AnalyticsFileItem(
                    id: url.path,
                    url: url,
                    granularity: granularity,
                    displayName: url.deletingPathExtension().lastPathComponent,
                    downloadDate: modDate,
                    sizeBytes: size
                ))
            }

            items.sort { $0.downloadDate > $1.downloadDate }
            if !items.isEmpty { grouped[granularity] = items }
        }

        uiState.itemsByGranularity = grouped
        // Drop any selection that no longer maps to a file on disk.
        let validIDs = Set(grouped.values.flatMap { $0 }.map(\.id))
        uiState.selectedIDs.formIntersection(validIDs)
    }

    // MARK: - Selection

    func toggleSelecting() {
        uiState.isSelecting.toggle()
        if !uiState.isSelecting {
            uiState.selectedIDs.removeAll()
        }
    }

    func toggle(id: String) {
        if uiState.selectedIDs.contains(id) {
            uiState.selectedIDs.remove(id)
        } else {
            uiState.selectedIDs.insert(id)
        }
    }

    func selectAll() {
        uiState.selectedIDs = Set(uiState.allItems.map(\.id))
    }

    func clearSelection() {
        uiState.selectedIDs.removeAll()
    }

    // MARK: - Delete

    /// Permanently removes the selected files from disk, then reloads and exits
    /// selection mode. The View gates this behind a confirmation alert.
    func delete() async {
        let targets = uiState.selectedItems
        guard !targets.isEmpty else { return }

        let fm = FileManager.default
        for item in targets {
            do {
                try fm.removeItem(at: item.url)
                Log.print.info("[AnalyticsFiles] Deleted \(item.url.lastPathComponent)")
            } catch {
                Log.print.error("[AnalyticsFiles] Delete failed for \(item.url.lastPathComponent): \(error.localizedDescription)")
            }
        }

        uiState.selectedIDs.removeAll()
        uiState.isSelecting = false
        await load()
    }

    // MARK: - Share

    /// Presents the selected files: a single file directly, or a fresh temp `.zip`
    /// of several. `isProcessing` is published while zipping.
    func share() async {
        let items = uiState.selectedItems
        guard !items.isEmpty else { return }

        if items.count == 1 {
            uiState.shareItem = ShareableFileURL(url: items[0].url)
            return
        }

        uiState.isProcessing = true
        defer { uiState.isProcessing = false }

        let fm = FileManager.default
        let dirName = "\(AnalyticsReportFileStore.sanitize(uiState.appName))-\(AnalyticsReportFileStore.sanitize(uiState.report.apiName))-files"
        let workDir = fm.temporaryDirectory.appendingPathComponent(dirName, isDirectory: true)

        do {
            // Start from a clean staging directory.
            try? fm.removeItem(at: workDir)
            try fm.createDirectory(at: workDir, withIntermediateDirectories: true)

            for item in items {
                // Prefix with the granularity so identical period keys from
                // different granularities don't collide in the flat zip dir.
                let prefix = item.granularity?.rawValue ?? "FILE"
                let destination = workDir.appendingPathComponent("\(prefix)-\(item.url.lastPathComponent)")
                try? fm.removeItem(at: destination)
                try fm.copyItem(at: item.url, to: destination)
            }

            let zip = try await Task.detached { try FileArchiver.zipDirectory(workDir) }.value
            uiState.shareItem = ShareableFileURL(url: zip)
            Log.print.info("[AnalyticsFiles] Zipped \(items.count) files → \(zip.lastPathComponent)")
        } catch {
            uiState.errorMessage = error.localizedDescription
            Log.print.error("[AnalyticsFiles] Zip failed: \(error.localizedDescription)")
        }
    }
}
