import Foundation
import APIProviderFirebase
import StackProtocols

// MARK: - Protocol

@MainActor
protocol FirebaseProjectListViewModelProtocol: ObservableObject {
    var uiState: FirebaseProjectListUiState { get set }
    func load() async
    func refresh() async
    /// "Sign in again" of `uiState.googleAccessPrompt`, then a reload.
    func resolveGoogleAccess() async
}

// MARK: - Project Model

struct FirebaseProjectModel: Identifiable, Hashable {
    let id: String
    var displayName: String
    var projectId: String
    var projectNumber: String?
    var state: String?
    var hostingSite: String?
    var storageBucket: String?
    var realtimeDatabaseInstance: String?
    var locationId: String?
}

// MARK: - UiState

struct FirebaseProjectListUiState {
    var account: AccountModel
    var projects: [FirebaseProjectModel] = []
    var isLoading = false
    var error: String?
    var searchQuery = ""
    var toastMessage: ToastMessage?
    /// Set when the account's Google sign-in expired or was revoked
    /// (`GoogleAccessRecovery`).
    var googleAccessPrompt: GoogleAccessPrompt?

    var filteredProjects: [FirebaseProjectModel] {
        let query = searchQuery.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return projects }
        return projects.filter {
            $0.displayName.lowercased().contains(query) ||
            $0.projectId.lowercased().contains(query)
        }
    }
}

// MARK: - Implementation

@MainActor
final class FirebaseProjectListViewModel: FirebaseProjectListViewModelProtocol {

    @Published var uiState: FirebaseProjectListUiState

    private let keychain: KeyStorable
    private let analytics: AnalyticsTracking
    private let googleAuth: any GoogleAuthServicing
    private let googleAccess: GoogleAccessRecovery

    init(
        account: AccountModel,
        keychain: KeyStorable = KeychainStorable.shared,
        analytics: AnalyticsTracking = AnalyticsService.shared,
        googleAuth: (any GoogleAuthServicing)? = nil
    ) {
        self.uiState = FirebaseProjectListUiState(account: account)
        self.keychain = keychain
        self.analytics = analytics
        let googleAuth = googleAuth ?? GoogleAuthService.shared
        self.googleAuth = googleAuth
        self.googleAccess = GoogleAccessRecovery(account: account, keychain: keychain, auth: googleAuth, analytics: analytics, screen: .firebaseProjectList)
    }

    func load() async {
        await performLoad()
    }

    /// Pull-to-refresh: same load, tracked as a `refresh` action with its outcome.
    func refresh() async {
        await performLoad()
        let failed = uiState.error != nil || uiState.googleAccessPrompt != nil
        analytics.track(.action(.refresh, on: .firebaseProjectList, result: failed ? .failure : .success))
    }

    func resolveGoogleAccess() async {
        guard let prompt = uiState.googleAccessPrompt, !prompt.isWorking else { return }
        guard await googleAccess.resolve(prompt, update: { uiState.googleAccessPrompt = $0 }) else { return }
        uiState.googleAccessPrompt = nil
        await performLoad()
    }

    private func performLoad() async {
        uiState.isLoading = true
        uiState.error = nil
        uiState.googleAccessPrompt = nil

        do {
            guard let provider = createProvider() else {
                uiState.error = String(localized: "No credentials found for this account.")
                uiState.isLoading = false
                return
            }

            var allProjects: [FirebaseProjectModel] = []
            var pageToken: String?

            repeat {
                let response = try await provider.request(
                    FirebaseAPI.v1beta1.projects.get(pageSize: 100, pageToken: pageToken)
                )

                let mapped = (response.results ?? []).map { project in
                    FirebaseProjectModel(
                        id: project.projectId ?? project.id,
                        displayName: project.displayName ?? project.projectId ?? "–",
                        projectId: project.projectId ?? "–",
                        projectNumber: project.projectNumber,
                        state: project.state?.rawValue,
                        hostingSite: project.resources?.hostingSite,
                        storageBucket: project.resources?.storageBucket,
                        realtimeDatabaseInstance: project.resources?.realtimeDatabaseInstance,
                        locationId: project.resources?.locationId
                    )
                }

                // A Google sign-in account is scoped to the project(s) picked in
                // Add Account (`appsBundles` holds their project IDs; nil/empty
                // ⇒ every project, as for service-account accounts).
                allProjects.append(contentsOf: mapped.filter { uiState.account.allowsApp(bundleId: $0.projectId) })
                pageToken = response.nextPageToken
            } while pageToken != nil

            uiState.projects = allProjects.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
            Log.print.info("[Firebase] Loaded \(allProjects.count) projects")
        } catch {
            if let prompt = googleAccess.prompt(for: error) {
                uiState.googleAccessPrompt = prompt
                Log.print.error("[Firebase] Load projects failed: \(error.localizedDescription)")
            } else if let message = googleAccess.unavailableMessage(for: error) {
                uiState.error = message
            } else {
                uiState.error = error.localizedDescription
                Log.print.error("[Firebase] Load projects failed: \(error.localizedDescription)")
            }
        }

        uiState.isLoading = false
    }

    // MARK: - Private

    private func createProvider() -> APIProviderFirebase? {
        guard let credentials: FirebaseCredentials = keychain.object(forKey: "credentials.\(uiState.account.id)") else { return nil }
        return BackendEnvironment.firebaseProviders.makeProvider(credentials: credentials, tokens: googleAuth)
    }
}
