import Foundation
import APIProviderFirebase

// MARK: - Protocol

@MainActor
protocol FirebaseProjectListViewModelProtocol: ObservableObject {
    var uiState: FirebaseProjectListUiState { get set }
    func load() async
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

    init(account: AccountModel, keychain: KeyStorable = KeychainStorable.shared) {
        self.uiState = FirebaseProjectListUiState(account: account)
        self.keychain = keychain
    }

    func load() async {
        uiState.isLoading = true
        uiState.error = nil

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

                allProjects.append(contentsOf: mapped)
                pageToken = response.nextPageToken
            } while pageToken != nil

            uiState.projects = allProjects.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
            Log.print.info("[Firebase] Loaded \(allProjects.count) projects")
        } catch {
            uiState.error = error.localizedDescription
            Log.print.error("[Firebase] Load projects failed: \(error.localizedDescription)")
        }

        uiState.isLoading = false
    }

    // MARK: - Private

    private func createProvider() -> APIProviderFirebase? {
        guard let credentials: FirebaseCredentials = keychain.object(forKey: "credentials.\(uiState.account.id)") else { return nil }
        guard let jsonData = credentials.serviceAccountJSON.data(using: .utf8) else { return nil }
        guard let config = try? FirebaseConfiguration(serviceAccountJSON: jsonData) else { return nil }
        return APIProviderFirebase(configuration: config)
    }
}
