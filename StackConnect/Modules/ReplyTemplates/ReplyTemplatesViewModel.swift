import Foundation
import StackProtocols

// MARK: - Protocol

@MainActor
protocol ReplyTemplatesViewModelProtocol: ObservableObject {
    var uiState: ReplyTemplatesUiState { get set }
    func load() async
    func save(title: String, body: String) async
    func update(_ template: ReplyTemplateModel, title: String, body: String) async
    func delete(_ template: ReplyTemplateModel) async
}

// MARK: - UiState

struct ReplyTemplatesUiState {
    /// Templates belonging to `accountId`, newest first.
    var templates: [ReplyTemplateModel] = []
    var isLoading = false
    var toastMessage: ToastMessage?
    /// Non-nil while the create/edit form is presented. `.create` for a new
    /// template, `.edit` carrying the template being modified.
    var form: ReplyTemplateFormMode?

    var isEmpty: Bool { templates.isEmpty }
}

/// Drives the create/edit form presentation. Being a single optional (rather
/// than a `Bool` + a separate payload) makes "editing with no template" and
/// "creating while an edit is pending" unrepresentable.
enum ReplyTemplateFormMode: Identifiable, Hashable {
    case create
    case edit(ReplyTemplateModel)

    var id: String {
        switch self {
        case .create: return "create"
        case .edit(let template): return "edit.\(template.id)"
        }
    }

    var template: ReplyTemplateModel? {
        switch self {
        case .create: return nil
        case .edit(let template): return template
        }
    }
}

// MARK: - Implementation

@MainActor
final class ReplyTemplatesViewModel: ReplyTemplatesViewModelProtocol {

    @Published var uiState = ReplyTemplatesUiState()

    private let accountId: String
    private let storage: PersistentStorable
    private let analytics: AnalyticsTracking

    init(
        accountId: String,
        storage: PersistentStorable? = nil,
        analytics: AnalyticsTracking = AnalyticsService.shared
    ) {
        self.accountId = accountId
        self.storage = storage ?? SwiftDataStorable.shared
        self.analytics = analytics
    }

    /// Loads the templates cached on the device. Templates are local-only, so
    /// this never hits the network.
    func load() async {
        uiState.isLoading = true
        defer { uiState.isLoading = false }

        do {
            let all: [ReplyTemplateModel] = try await storage.fetchAll(ReplyTemplateModel.self)
            uiState.templates = Self.sorted(all.filter { $0.accountId == accountId })
        } catch {
            Log.print.error("[ReplyTemplates] Failed to load templates: \(error.localizedDescription)")
            uiState.toastMessage = ToastMessage(
                String(localized: "Failed to load templates"),
                icon: "exclamationmark.triangle.fill"
            )
        }
    }

    func save(title: String, body: String) async {
        analytics.track(.buttonTap(.save, on: .replyTemplateForm))
        let template = ReplyTemplateModel(
            accountId: accountId,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            body: body.trimmingCharacters(in: .whitespacesAndNewlines)
        )

        do {
            try await storage.save(template, id: template.id)
            uiState.templates = Self.sorted(uiState.templates + [template])
            uiState.toastMessage = ToastMessage(String(localized: "Template saved"))
            analytics.track(.action(.createReplyTemplate, on: .replyTemplateForm, result: .success))
        } catch {
            analytics.track(.action(.createReplyTemplate, on: .replyTemplateForm, result: .failure))
            Log.print.error("[ReplyTemplates] Failed to save template: \(error.localizedDescription)")
            uiState.toastMessage = ToastMessage(
                String(localized: "Failed to save template"),
                icon: "exclamationmark.triangle.fill"
            )
        }
    }

    func update(_ template: ReplyTemplateModel, title: String, body: String) async {
        analytics.track(.buttonTap(.save, on: .replyTemplateForm))
        var updated = template
        updated.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.body = body.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.updatedAt = Date()

        do {
            try await storage.save(updated, id: updated.id)
            var templates = uiState.templates
            if let index = templates.firstIndex(where: { $0.id == updated.id }) {
                templates[index] = updated
            } else {
                templates.append(updated)
            }
            uiState.templates = Self.sorted(templates)
            uiState.toastMessage = ToastMessage(String(localized: "Template updated"))
            analytics.track(.action(.updateReplyTemplate, on: .replyTemplateForm, result: .success))
        } catch {
            analytics.track(.action(.updateReplyTemplate, on: .replyTemplateForm, result: .failure))
            Log.print.error("[ReplyTemplates] Failed to update template: \(error.localizedDescription)")
            uiState.toastMessage = ToastMessage(
                String(localized: "Failed to update template"),
                icon: "exclamationmark.triangle.fill"
            )
        }
    }

    func delete(_ template: ReplyTemplateModel) async {
        analytics.track(.buttonTap(.delete, on: .replyTemplates))
        do {
            try await storage.delete(ReplyTemplateModel.self, id: template.id)
            uiState.templates.removeAll { $0.id == template.id }
            uiState.toastMessage = ToastMessage(String(localized: "Template deleted"), icon: "trash")
            analytics.track(.action(.deleteReplyTemplate, on: .replyTemplates, result: .success))
        } catch {
            analytics.track(.action(.deleteReplyTemplate, on: .replyTemplates, result: .failure))
            Log.print.error("[ReplyTemplates] Failed to delete template: \(error.localizedDescription)")
            uiState.toastMessage = ToastMessage(
                String(localized: "Failed to delete template"),
                icon: "exclamationmark.triangle.fill"
            )
        }
    }

    // MARK: - Private

    /// `PersistentStorable.fetchAll` gives no ordering guarantee, so the order is
    /// imposed here: newest first, tie-broken by `id` for a total (stable) order.
    private static func sorted(_ templates: [ReplyTemplateModel]) -> [ReplyTemplateModel] {
        templates.sorted { lhs, rhs in
            if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
            return lhs.id < rhs.id
        }
    }
}
