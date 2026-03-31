import Foundation
import APIProviderFirebase

// MARK: - Protocol

@MainActor
protocol RemoteConfigViewModelProtocol: ObservableObject {
    var uiState: RemoteConfigUiState { get set }
    func load() async
    func saveTemplate() async
    func addParameter(_ name: String, parameter: RemoteConfigParameter)
    func updateParameter(_ name: String, parameter: RemoteConfigParameter)
    func deleteParameter(_ name: String)
    func addCondition(_ condition: RemoteConfigCondition)
    func updateCondition(at index: Int, with condition: RemoteConfigCondition)
    func deleteCondition(at index: Int)
    func moveCondition(from source: IndexSet, to destination: Int)
    func duplicateCondition(_ condition: RemoteConfigCondition)
}

// MARK: - Parameter Model

struct RemoteConfigParameterItem: Identifiable, Hashable {
    let id: String
    var name: String
    var parameter: RemoteConfigParameter

    var displayValue: String {
        if let value = parameter.defaultValue?.value {
            return value
        } else if parameter.defaultValue?.useInAppDefault == true {
            return String(localized: "(in-app default)")
        }
        return "–"
    }

    var valueType: RemoteConfigParameter.ValueType {
        parameter.valueType ?? .string
    }

    var conditionNames: [String] {
        Array(parameter.conditionalValues?.keys ?? [:].keys).sorted()
    }
}

// MARK: - UiState

struct RemoteConfigUiState {
    var project: FirebaseProjectModel
    var account: AccountModel
    var parameters: [RemoteConfigParameterItem] = []
    var conditions: [RemoteConfigCondition] = []
    var version: RemoteConfigVersion?
    var isLoading = false
    var isSaving = false
    var error: String?
    var toastMessage: ToastMessage?
    var selectedParameter: RemoteConfigParameterItem?
    var showCreateParameter = false
    var etag: String = "*"
    var searchQuery = ""

    var filteredParameters: [RemoteConfigParameterItem] {
        let query = searchQuery.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return parameters }
        return parameters.filter {
            $0.name.lowercased().contains(query) ||
            $0.displayValue.lowercased().contains(query)
        }
    }
}

// MARK: - Implementation

@MainActor
final class RemoteConfigViewModel: RemoteConfigViewModelProtocol {

    @Published var uiState: RemoteConfigUiState

    private let keychain: KeyStorable

    // Internal template (the full template we work with)
    private var currentTemplate: RemoteConfigTemplate = RemoteConfigTemplate()

    init(
        project: FirebaseProjectModel,
        account: AccountModel,
        keychain: KeyStorable = KeychainStorable.shared
    ) {
        self.uiState = RemoteConfigUiState(project: project, account: account)
        self.keychain = keychain
    }

    // MARK: - Load

    func load() async {
        uiState.isLoading = true
        uiState.error = nil

        guard let provider = createProvider() else {
            uiState.error = String(localized: "No credentials found for this account.")
            uiState.isLoading = false
            return
        }

        do {
            let endpoint = FirebaseAPI.v1.remoteConfig(projectId: uiState.project.projectId).get()
            let (template, headers) = try await provider.requestWithHeaders(endpoint)

            currentTemplate = template
            uiState.etag = (headers["ETag"] as? String) ?? (headers["etag"] as? String) ?? "*"
            uiState.version = template.version
            uiState.conditions = template.conditions ?? []
            uiState.parameters = buildParameterItems(from: template)

            Log.print.info("[RemoteConfig] Loaded \(self.uiState.parameters.count) parameters, \(self.uiState.conditions.count) conditions for project \(self.uiState.project.projectId)")
        } catch {
            uiState.error = error.localizedDescription
            Log.print.error("[RemoteConfig] Load failed: \(error.localizedDescription)")
        }

        uiState.isLoading = false
    }

    // MARK: - Save

    func saveTemplate() async {
        guard let provider = createProvider() else { return }
        uiState.isSaving = true

        // Rebuild template from current state
        let updatedTemplate = buildTemplate()

        do {
            let endpoint = FirebaseAPI.v1.remoteConfig(projectId: uiState.project.projectId)
                .put(updatedTemplate, etag: uiState.etag)
            let (saved, headers) = try await provider.requestWithHeaders(endpoint)

            currentTemplate = saved
            uiState.etag = (headers["ETag"] as? String) ?? (headers["etag"] as? String) ?? "*"
            uiState.version = saved.version
            uiState.conditions = saved.conditions ?? []
            uiState.parameters = buildParameterItems(from: saved)

            uiState.toastMessage = ToastMessage(String(localized: "Config published"), icon: "checkmark.circle.fill")
            Log.print.info("[RemoteConfig] Template saved for \(self.uiState.project.projectId)")
        } catch {
            uiState.toastMessage = ToastMessage(String(localized: "Failed to publish"), icon: "exclamationmark.triangle.fill")
            Log.print.error("[RemoteConfig] Save failed: \(error.localizedDescription)")
        }

        uiState.isSaving = false
    }

    // MARK: - Parameters

    func addParameter(_ name: String, parameter: RemoteConfigParameter) {
        let item = RemoteConfigParameterItem(id: name, name: name, parameter: parameter)
        uiState.parameters.append(item)
        uiState.parameters.sort { $0.name < $1.name }
    }

    func updateParameter(_ name: String, parameter: RemoteConfigParameter) {
        if let idx = uiState.parameters.firstIndex(where: { $0.name == name }) {
            uiState.parameters[idx] = RemoteConfigParameterItem(id: name, name: name, parameter: parameter)
        }
    }

    func deleteParameter(_ name: String) {
        uiState.parameters.removeAll { $0.name == name }
        if uiState.selectedParameter?.name == name {
            uiState.selectedParameter = nil
        }
    }

    // MARK: - Conditions

    func addCondition(_ condition: RemoteConfigCondition) {
        guard !uiState.conditions.contains(where: { $0.name == condition.name }) else { return }
        uiState.conditions.append(condition)
    }

    func updateCondition(at index: Int, with condition: RemoteConfigCondition) {
        guard index < uiState.conditions.count else { return }
        uiState.conditions[index] = condition
    }

    func deleteCondition(at index: Int) {
        guard index < uiState.conditions.count else { return }
        uiState.conditions.remove(at: index)
    }

    func moveCondition(from source: IndexSet, to destination: Int) {
        uiState.conditions.move(fromOffsets: source, toOffset: destination)
    }

    func duplicateCondition(_ condition: RemoteConfigCondition) {
        var copy = condition
        copy = RemoteConfigCondition(
            name: condition.name + "_copy",
            expression: condition.expression,
            tagColor: condition.tagColor,
            description: condition.description
        )
        uiState.conditions.append(copy)
    }

    // MARK: - Private Helpers

    private func buildParameterItems(from template: RemoteConfigTemplate) -> [RemoteConfigParameterItem] {
        var items: [RemoteConfigParameterItem] = []

        // Top-level parameters
        for (name, param) in template.parameters ?? [:] {
            items.append(RemoteConfigParameterItem(id: name, name: name, parameter: param))
        }

        // Parameters inside groups
        for (_, group) in template.parameterGroups ?? [:] {
            for (name, param) in group.parameters ?? [:] {
                if !items.contains(where: { $0.name == name }) {
                    items.append(RemoteConfigParameterItem(id: name, name: name, parameter: param))
                }
            }
        }

        return items.sorted { $0.name < $1.name }
    }

    private func buildTemplate() -> RemoteConfigTemplate {
        // Collect all parameter keys that live inside groups so we can
        // avoid duplicating them at the top level (Firebase rejects duplicates).
        var groupParamKeys = Set<String>()
        for (_, group) in currentTemplate.parameterGroups ?? [:] {
            for key in group.parameters?.keys ?? [:].keys {
                groupParamKeys.insert(key)
            }
        }

        // Top-level parameters: only those NOT owned by any group.
        var params: [String: RemoteConfigParameter] = [:]
        for item in uiState.parameters where !groupParamKeys.contains(item.name) {
            params[item.name] = item.parameter
        }

        // Rebuild groups, applying any edits the user made to group-owned parameters.
        var updatedGroups = currentTemplate.parameterGroups
        if var groups = updatedGroups {
            for (groupName, group) in groups {
                var groupParams = group.parameters ?? [:]
                for key in groupParams.keys {
                    if let item = uiState.parameters.first(where: { $0.name == key }) {
                        groupParams[key] = item.parameter
                    }
                }
                groups[groupName] = RemoteConfigParameterGroup(
                    description: group.description,
                    parameters: groupParams
                )
            }
            updatedGroups = groups
        }

        return RemoteConfigTemplate(
            conditions: uiState.conditions,
            parameters: params,
            parameterGroups: updatedGroups
        )
    }

    private func createProvider() -> APIProviderFirebase? {
        guard let credentials: FirebaseCredentials = keychain.object(forKey: "credentials.\(uiState.account.id)") else { return nil }
        guard let jsonData = credentials.serviceAccountJSON.data(using: .utf8) else { return nil }
        guard let config = try? FirebaseConfiguration(serviceAccountJSON: jsonData) else { return nil }
        return APIProviderFirebase(configuration: config)
    }
}
