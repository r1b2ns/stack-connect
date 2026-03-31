import Foundation
import SwiftUI

// MARK: - Protocol

@MainActor
protocol FirebaseProjectDetailViewModelProtocol: ObservableObject {
    var uiState: FirebaseProjectDetailUiState { get set }
    func load() async
    func moveItem(from source: IndexSet, to destination: Int) async
}

// MARK: - Menu Item

struct FirebaseMenuItem: Identifiable, Hashable {
    let id: String
    let title: String
    let icon: String
    let color: Color

    static func item(for id: String) -> FirebaseMenuItem? {
        allItems.first { $0.id == id }
    }

    static let allItems: [FirebaseMenuItem] = [
        FirebaseMenuItem(id: "apps", title: String(localized: "Apps"), icon: "app.fill", color: .blue),
        FirebaseMenuItem(id: "remoteConfig", title: String(localized: "Remote Config"), icon: "slider.horizontal.3", color: .green),
        FirebaseMenuItem(id: "messaging", title: String(localized: "Messaging"), icon: "bell.fill", color: .purple),
        FirebaseMenuItem(id: "analyticsDashboard", title: String(localized: "Analytics Dashboard"), icon: "chart.bar.fill", color: .cyan),
    ]
}

// MARK: - UiState

struct FirebaseProjectDetailUiState {
    var project: FirebaseProjectModel
    var account: AccountModel
    var menuItems: [FirebaseMenuItem] = FirebaseMenuItem.allItems
    var isLoading = false
}

// MARK: - Implementation

@MainActor
final class FirebaseProjectDetailViewModel: FirebaseProjectDetailViewModelProtocol {

    @Published var uiState: FirebaseProjectDetailUiState

    private let storage: PersistentStorable

    init(
        project: FirebaseProjectModel,
        account: AccountModel,
        storage: PersistentStorable? = nil
    ) {
        self.uiState = FirebaseProjectDetailUiState(project: project, account: account)
        self.storage = storage ?? SwiftDataStorable.shared
    }

    func load() async {
        uiState.isLoading = true

        do {
            if let saved: FirebaseProjectMenuOrder = try await storage.fetch(
                FirebaseProjectMenuOrder.self,
                id: storageKey
            ) {
                let ordered = saved.orderedItems.compactMap { FirebaseMenuItem.item(for: $0) }
                // Append any new items not yet in saved order
                let savedIds = Set(saved.orderedItems)
                let missing = FirebaseMenuItem.allItems.filter { !savedIds.contains($0.id) }
                uiState.menuItems = ordered + missing
            }
        } catch {
            Log.print.error("[FirebaseProjectDetail] Failed to load menu order: \(error.localizedDescription)")
        }

        uiState.isLoading = false
    }

    func moveItem(from source: IndexSet, to destination: Int) async {
        uiState.menuItems.move(fromOffsets: source, toOffset: destination)

        let order = FirebaseProjectMenuOrder(
            projectId: uiState.project.projectId,
            orderedItems: uiState.menuItems.map(\.id)
        )

        do {
            try await storage.save(order, id: storageKey)
            Log.print.info("[FirebaseProjectDetail] Saved menu order for \(self.uiState.project.projectId)")
        } catch {
            Log.print.error("[FirebaseProjectDetail] Failed to save menu order: \(error.localizedDescription)")
        }
    }

    private var storageKey: String {
        "firebase-menu-order.\(uiState.project.projectId)"
    }
}
