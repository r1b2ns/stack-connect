import SwiftUI
import UIKit

// MARK: - Factory

@MainActor
struct FirebaseProjectDetailViewFactory {
    static func build(project: FirebaseProjectModel, account: AccountModel) -> some View {
        FirebaseProjectDetailEntry(project: project, account: account)
    }
}

// MARK: - Entry

private struct FirebaseProjectDetailEntry: View {
    let project: FirebaseProjectModel
    let account: AccountModel

    @StateObject private var viewModel: FirebaseProjectDetailViewModel

    init(project: FirebaseProjectModel, account: AccountModel) {
        self.project = project
        self.account = account
        _viewModel = StateObject(wrappedValue: FirebaseProjectDetailViewModel(project: project, account: account))
    }

    var body: some View {
        FirebaseProjectDetailView(viewModel: viewModel)
    }
}

// MARK: - View

struct FirebaseProjectDetailView<ViewModel: FirebaseProjectDetailViewModelProtocol>: View {

    @ObservedObject var viewModel: ViewModel
    @EnvironmentObject private var homeCoordinator: HomeCoordinator

    var body: some View {
        List {
            buildProjectInfoSection()
            buildMenuSection()
        }
        .navigationTitle(viewModel.uiState.project.displayName)
        .trackScreen(.firebaseProjectDetail)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { buildToolbar() }
        .task { await viewModel.load() }
    }

    // MARK: - Project Info

    private func buildProjectInfoSection() -> some View {
        Section {
            HStack {
                Label(String(localized: "Project ID"), systemImage: "number")
                Spacer()
                Text(viewModel.uiState.project.projectId)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                StackTrackedButton(.copy, on: .firebaseProjectDetail) {
                    UIPasteboard.general.string = viewModel.uiState.project.projectId
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "Copy \(String(localized: "Project ID"))"))
            }

            if let location = viewModel.uiState.project.locationId {
                HStack {
                    Label(String(localized: "Location"), systemImage: "mappin.circle.fill")
                    Spacer()
                    Text(location)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let bucket = viewModel.uiState.project.storageBucket {
                HStack {
                    Label(String(localized: "Storage"), systemImage: "externaldrive.fill")
                    Spacer()
                    Text(bucket)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Project")
        }
    }

    // MARK: - Menu

    private func buildMenuSection() -> some View {
        Section {
            ForEach(viewModel.uiState.menuItems) { item in
                StackTrackedButton(item.analyticsButton, on: .firebaseProjectDetail) {
                    handleMenuTap(item)
                } label: {
                    StackListRow(icon: item.icon, iconColor: item.color, title: item.title)
                }
                .foregroundStyle(.primary)
            }
            .onMove { source, destination in
                Task { await viewModel.moveItem(from: source, to: destination) }
            }
        } header: {
            Text("Services")
        }
    }

    // MARK: - Menu Actions

    private func handleMenuTap(_ item: FirebaseMenuItem) {
        switch item.id {
        case "apps":
            homeCoordinator.navigateToFirebaseAppList(
                project: viewModel.uiState.project,
                account: viewModel.uiState.account
            )
        case "remoteConfig":
            homeCoordinator.navigateToRemoteConfig(
                project: viewModel.uiState.project,
                account: viewModel.uiState.account
            )
        case "analyticsDashboard":
            homeCoordinator.navigateToAnalyticsDashboard(
                project: viewModel.uiState.project,
                account: viewModel.uiState.account
            )
        case "messaging":
            homeCoordinator.navigateToMessaging(
                project: viewModel.uiState.project,
                account: viewModel.uiState.account
            )
        default:
            break
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private func buildToolbar() -> some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            EditButton()
        }
    }
}

// MARK: - Analytics

private extension FirebaseMenuItem {
    /// The tap identifier of this service row (fixed menu ids only).
    var analyticsButton: AnalyticsButton {
        switch id {
        case "apps": return .apps
        case "remoteConfig": return .remoteConfig
        case "messaging": return .messaging
        case "analyticsDashboard": return .analytics
        default: return .select
        }
    }
}
