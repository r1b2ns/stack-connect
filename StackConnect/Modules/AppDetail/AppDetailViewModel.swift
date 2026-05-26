import Foundation

// MARK: - Protocol

@MainActor
protocol AppDetailViewModelProtocol: ObservableObject {
    var uiState: AppDetailUiState { get set }
    func refresh() async
    func createVersions() async
    func deleteVersion(id: String) async
    func submitForReview(version: AppStoreVersionModel) async
    func cancelReview(version: AppStoreVersionModel) async
    func releaseVersion(_ version: AppStoreVersionModel) async
    func rejectVersion(_ version: AppStoreVersionModel) async
    func toggleFavorite() async
    func toggleArchive() async
}

// MARK: - UiState

struct AppDetailUiState {
    var app: AppModel
    var account: AccountModel
    var versions: [AppStoreVersionModel] = []
    var isLoading = false
    var syncError: String?

    // Version actions
    var isPerformingAction = false
    var actionError: String?
    var confirmAction: VersionAction?
    var toastMessage: ToastMessage?

    // Review issues
    var hasReviewIssues = false

    // Create Platform sheet
    var showCreatePlatform = false
    var selectedPlatforms: Set<AppPlatform> = []
    var newVersionString = "1.0.0"
    var isCreating = false
    var createError: String?

    var platformSections: [PlatformSection] {
        let grouped = Dictionary(grouping: versions) { $0.platform ?? .ios }
        return grouped
            .sorted { $0.key.displayName < $1.key.displayName }
            .map { PlatformSection(platform: $0.key, versions: Array($0.value.prefix(2))) }
    }
}

struct PlatformSection: Identifiable {
    let platform: AppPlatform
    let versions: [AppStoreVersionModel]
    var id: String { platform.rawValue }
}

enum VersionAction: Identifiable {
    case submitForReview(AppStoreVersionModel)
    case cancelReview(AppStoreVersionModel)
    case release(AppStoreVersionModel)
    case reject(AppStoreVersionModel)
    case delete(AppStoreVersionModel)

    var id: String {
        switch self {
        case .submitForReview(let v): return "submit-\(v.id)"
        case .cancelReview(let v):    return "cancel-\(v.id)"
        case .release(let v):         return "release-\(v.id)"
        case .reject(let v):          return "reject-\(v.id)"
        case .delete(let v):          return "delete-\(v.id)"
        }
    }

    var title: String {
        switch self {
        case .submitForReview: return String(localized: "Submit for Review")
        case .cancelReview:    return String(localized: "Cancel Review")
        case .release:         return String(localized: "Release Version")
        case .reject:          return String(localized: "Reject Version")
        case .delete:          return String(localized: "Delete Version")
        }
    }

    var message: String {
        switch self {
        case .submitForReview(let v):
            return String(localized: "Are you sure you want to submit version \(v.versionString ?? "–") for review?")
        case .cancelReview(let v):
            return String(localized: "Are you sure you want to cancel the review for version \(v.versionString ?? "–")?")
        case .release(let v):
            return String(localized: "Are you sure you want to release version \(v.versionString ?? "–") to the App Store?")
        case .reject(let v):
            return String(localized: "Are you sure you want to reject version \(v.versionString ?? "–")? This action cannot be undone.")
        case .delete(let v):
            return String(localized: "Are you sure you want to delete version \(v.versionString ?? "–")? This action cannot be undone.")
        }
    }

    var confirmLabel: String {
        switch self {
        case .submitForReview: return String(localized: "Submit")
        case .cancelReview:    return String(localized: "Cancel Review")
        case .release:         return String(localized: "Release")
        case .reject:          return String(localized: "Reject")
        case .delete:          return String(localized: "Delete")
        }
    }

    var isDestructive: Bool {
        switch self {
        case .submitForReview, .release: return false
        case .cancelReview, .reject, .delete: return true
        }
    }
}

// MARK: - Implementation

@MainActor
final class AppDetailViewModel: AppDetailViewModelProtocol {

    @Published var uiState: AppDetailUiState

    private let storage: PersistentStorable
    private let keychain: KeyStorable

    init(
        app: AppModel,
        account: AccountModel,
        storage: PersistentStorable? = nil,
        keychain: KeyStorable = KeychainStorable.shared
    ) {
        self.uiState = AppDetailUiState(app: app, account: account)
        self.storage = storage ?? SwiftDataStorable.shared
        self.keychain = keychain
    }

    func refresh() async {
        let versionsLimit = 20

        // 1. Load cached versions from SwiftData FIRST (offline-first)
        do {
            let cached: [AppStoreVersionModel] = try await storage.fetchAll(AppStoreVersionModel.self)
            let appVersions = cached.filter {
                $0.appId == self.uiState.app.id
            }.sorted(by: {
                $0.versionString ?? "" > $1.versionString ?? ""
            })

            if !appVersions.isEmpty {
                uiState.versions = appVersions
                Log.print.info("[AppDetail] Loaded \(appVersions.count) cached versions for \(self.uiState.app.name)")
            }
        } catch {
            Log.print.error("[AppDetail] Failed to load cached versions: \(error.localizedDescription)")
        }

        // 2. Load cached app data (icon, state, etc.)
        do {
            if let cachedApp: AppModel = try await storage.fetch(AppModel.self, id: "\(self.uiState.account.id).\(self.uiState.app.id)") {
                if let icon = cachedApp.iconUrl { uiState.app.iconUrl = icon }
                if let state = cachedApp.appStoreState { uiState.app.appStoreState = state }
                if let version = cachedApp.versionString { uiState.app.versionString = version }
                uiState.app.hasReviewPending = cachedApp.hasReviewPending
                uiState.app.isFavorite = cachedApp.isFavorite
            }
        } catch {
            Log.print.error("[AppDetail] Failed to load cached app: \(error.localizedDescription)")
        }

        // 3. Only show loading spinner if we have no cached data
        if uiState.versions.isEmpty {
            uiState.isLoading = true
        }

        // 4. Sync from API
        do {
            guard let credentials: AppleCredentials = keychain.object(forKey: "credentials.\(self.uiState.account.id)") else {
                uiState.isLoading = false
                return
            }

            let connection = AppleAccountConnection(credentials: credentials)

            // Fetch versions + icon/state + review submissions in parallel
            async let versionsResult = connection.fetchAppStoreVersions(appId: self.uiState.app.id, limit: versionsLimit)
            async let iconResult = connection.fetchIconUrl(appId: self.uiState.app.id)
            async let stateResult = connection.fetchAppStoreVersion(appId: self.uiState.app.id)
            async let submissionsResult = connection.fetchReviewSubmissions(appId: self.uiState.app.id)

            let versions = try await versionsResult
            let icon = await iconResult
            let state = await stateResult
            let submissions = (try? await submissionsResult) ?? []

            uiState.hasReviewIssues = submissions.contains { $0.state == "UNRESOLVED_ISSUES" }

            // Update app model
            if let icon { uiState.app.iconUrl = icon }
            if let s = state.state { uiState.app.appStoreState = AppStoreState(rawValue: s) }
            if let v = state.version { uiState.app.versionString = v }

            // Mark review pending flag based on current state
            uiState.app.hasReviewPending = uiState.app.appStoreState?.isReviewPending ?? false

            uiState.versions = versions

            // 5. Persist to SwiftData in a detached Task so a view dismissal mid-loop
            // (which cancels `.task`) doesn't truncate the writes.
            persistSync(app: uiState.app, versions: versions, limit: versionsLimit)

        } catch {
            uiState.syncError = error.localizedDescription
            Log.print.error("[AppDetail] Sync failed: \(error.localizedDescription)")
        }

        uiState.isLoading = false
    }

    func createVersions() async {
        guard !uiState.selectedPlatforms.isEmpty,
              !uiState.newVersionString.trimmingCharacters(in: .whitespaces).isEmpty else { return }

        uiState.isCreating = true
        uiState.createError = nil

        do {
            guard let credentials: AppleCredentials = keychain.object(forKey: "credentials.\(self.uiState.account.id)") else {
                uiState.isCreating = false
                return
            }

            let connection = AppleAccountConnection(credentials: credentials)

            for platform in uiState.selectedPlatforms {
                let request = CreateAppVersionRequest(
                    appId: uiState.app.id,
                    platform: platform,
                    version: uiState.newVersionString.trimmingCharacters(in: .whitespaces)
                )
                let created = try await connection.createAppStoreVersion(request: request)
                try await storage.save(created, id: "version.\(created.id)")
                Log.print.info("[AppDetail] Created version \(self.uiState.newVersionString) for \(platform.displayName)")
            }

            uiState.showCreatePlatform = false
            uiState.selectedPlatforms = []
            uiState.newVersionString = "1.0.0"

            await refresh()

        } catch {
            uiState.createError = error.localizedDescription
            Log.print.error("[AppDetail] Create version failed: \(error.localizedDescription)")
        }

        uiState.isCreating = false
    }

    func deleteVersion(id: String) async {
        do {
            guard let credentials: AppleCredentials = keychain.object(forKey: "credentials.\(self.uiState.account.id)") else { return }

            let connection = AppleAccountConnection(credentials: credentials)
            try await connection.deleteAppStoreVersion(id: id)
            try await storage.delete(AppStoreVersionModel.self, id: "version.\(id)")
            uiState.versions.removeAll { $0.id == id }
            uiState.toastMessage = ToastMessage(String(localized: "Version deleted"), icon: "trash")
            Log.print.info("[AppDetail] Deleted version \(id)")
        } catch {
            uiState.actionError = error.localizedDescription
            Log.print.error("[AppDetail] Delete version failed: \(error.localizedDescription)")
        }
    }

    func submitForReview(version: AppStoreVersionModel) async {
        uiState.isPerformingAction = true
        uiState.actionError = nil

        do {
            guard let connection = createConnection() else { return }
            try await connection.submitForReview(appId: version.appId, versionId: version.id, platform: version.platform)
            uiState.toastMessage = ToastMessage(String(localized: "Submitted for review"), icon: "paperplane.fill")
            Log.print.info("[AppDetail] Submitted version \(version.id) for review")
            await refresh()
        } catch {
            uiState.actionError = error.localizedDescription
            Log.print.error("[AppDetail] Submit for review failed: \(error.localizedDescription)")
        }

        uiState.isPerformingAction = false
    }

    func cancelReview(version: AppStoreVersionModel) async {
        uiState.isPerformingAction = true
        uiState.actionError = nil

        do {
            guard let connection = createConnection() else { return }
            try await connection.cancelReview(appId: version.appId)
            uiState.toastMessage = ToastMessage(String(localized: "Review cancelled"), icon: "xmark.circle.fill")
            Log.print.info("[AppDetail] Cancelled review for version \(version.id)")
            await refresh()
        } catch {
            uiState.actionError = error.localizedDescription
            Log.print.error("[AppDetail] Cancel review failed: \(error.localizedDescription)")
        }

        uiState.isPerformingAction = false
    }

    func releaseVersion(_ version: AppStoreVersionModel) async {
        uiState.isPerformingAction = true
        uiState.actionError = nil

        do {
            guard let connection = createConnection() else { return }
            try await connection.releaseVersion(versionId: version.id)
            uiState.toastMessage = ToastMessage(String(localized: "Version released"), icon: "checkmark.circle.fill")
            Log.print.info("[AppDetail] Released version \(version.id)")
            await refresh()
        } catch {
            uiState.actionError = error.localizedDescription
            Log.print.error("[AppDetail] Release version failed: \(error.localizedDescription)")
        }

        uiState.isPerformingAction = false
    }

    func rejectVersion(_ version: AppStoreVersionModel) async {
        uiState.isPerformingAction = true
        uiState.actionError = nil

        do {
            guard let connection = createConnection() else { return }
            try await connection.rejectVersion(appId: version.appId)
            uiState.toastMessage = ToastMessage(String(localized: "Version rejected"), icon: "xmark.circle.fill")
            Log.print.info("[AppDetail] Rejected version \(version.id)")
            await refresh()
        } catch {
            uiState.actionError = error.localizedDescription
            Log.print.error("[AppDetail] Reject version failed: \(error.localizedDescription)")
        }

        uiState.isPerformingAction = false
    }

    func toggleFavorite() async {
        uiState.app.isFavorite.toggle()
        do {
            try await storage.save(uiState.app, id: "\(uiState.account.id).\(uiState.app.id)")
            let text = uiState.app.isFavorite
                ? String(localized: "Added to favorites")
                : String(localized: "Removed from favorites")
            uiState.toastMessage = ToastMessage(text, icon: uiState.app.isFavorite ? "star.fill" : "star")
            Log.print.info("[AppDetail] Toggled favorite for \(self.uiState.app.name): \(self.uiState.app.isFavorite)")
        } catch {
            uiState.app.isFavorite.toggle() // revert
            Log.print.error("[AppDetail] Toggle favorite failed: \(error.localizedDescription)")
        }
    }

    func toggleArchive() async {
        uiState.app.isArchived.toggle()
        do {
            try await storage.save(uiState.app, id: "\(uiState.account.id).\(uiState.app.id)")
            let text = uiState.app.isArchived
                ? String(localized: "Archived")
                : String(localized: "Unarchived")
            uiState.toastMessage = ToastMessage(text, icon: uiState.app.isArchived ? "archivebox.fill" : "archivebox")
            Log.print.info("[AppDetail] Toggled archive for \(self.uiState.app.name): \(self.uiState.app.isArchived)")
        } catch {
            uiState.app.isArchived.toggle() // revert
            Log.print.error("[AppDetail] Toggle archive failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Private

    private func persistSync(app: AppModel, versions: [AppStoreVersionModel], limit: Int) {
        let storage = self.storage
        let accountId = uiState.account.id
        let appName = app.name
        let appKey = "\(accountId).\(app.id)"
        let appId = app.id

        Task.detached(priority: .utility) {
            do {
                try await storage.save(app, id: appKey)
                Log.print.info("[AppDetail] Persisted app data for \(appName)")
            } catch {
                Log.print.error("[AppDetail] Failed to persist app: \(error.localizedDescription)")
            }

            for version in versions {
                do {
                    try await storage.save(version, id: "version.\(version.id)")
                } catch {
                    Log.print.error("[AppDetail] Failed to persist version \(version.id): \(error.localizedDescription)")
                }
            }

            // Reconcile: drop cached versions that no longer exist remotely.
            // Only safe when the API didn't hit the cap — otherwise older versions
            // we didn't fetch would be wrongly deleted.
            if versions.count < limit {
                await Self.pruneStaleVersions(storage: storage, appId: appId, appName: appName, returned: versions)
            }

            Log.print.info("[AppDetail] Synced \(versions.count) versions for \(appName)")
        }
    }

    private static func pruneStaleVersions(
        storage: PersistentStorable,
        appId: String,
        appName: String,
        returned: [AppStoreVersionModel]
    ) async {
        let returnedIds = Set(returned.map { $0.id })
        do {
            let allCached: [AppStoreVersionModel] = try await storage.fetchAll(AppStoreVersionModel.self)
            let stale = allCached.filter { $0.appId == appId && !returnedIds.contains($0.id) }
            for version in stale {
                try? await storage.delete(AppStoreVersionModel.self, id: "version.\(version.id)")
            }
            if !stale.isEmpty {
                Log.print.info("[AppDetail] Pruned \(stale.count) stale cached versions for \(appName)")
            }
        } catch {
            Log.print.error("[AppDetail] Reconciliation failed: \(error.localizedDescription)")
        }
    }

    private func createConnection() -> AppleAccountConnection? {
        guard let credentials: AppleCredentials = keychain.object(forKey: "credentials.\(uiState.account.id)") else {
            return nil
        }
        return AppleAccountConnection(credentials: credentials)
    }
}
