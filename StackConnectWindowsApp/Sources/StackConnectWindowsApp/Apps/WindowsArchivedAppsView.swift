import SwiftCrossUI
import StackHomeCore
import WindowsAppCore

// T-W07 — Archived Apps screen for the Windows GUI.
//
// Displays the archived apps belonging to a single Apple account, with a
// toolbar (back + title + explicit Refresh button), a list of archived apps
// each with a Restore button, a loading state, and an empty archived state
// ("No archived apps") when nothing is archived.
//
// Layout follows the Windows app convention: content capped at 860px, padded
// 16px, with a `ScrollView` + `VStack`. The toolbar uses `WindowsBackButtonView`
// for the "< Back" action (pops to the prior screen).
//
// Restore flow (AC-W04-4): the Restore button on each row calls
// `model.restoreApp(appId:)` (which sets the confirmation intent) and then
// pushes a restore-confirm route via the coordinator. On confirm, the
// confirmation screen calls the model's `restoreAppConfirmed` (the model is
// stored in RootView and shared between both routes). On cancel/back, calls
// `model.cancelRestore` and pops. This uses a PUSHED ROUTE (TC-072), not an
// alert/sheet.
//
// TC-070: Refresh is an explicit button in the toolbar. There is NO
// pull-to-refresh (SwiftCrossUI has no pull-to-refresh support).

struct WindowsArchivedAppsView: View {

    /// The account id this list displays archived apps for.
    let accountId: String
    /// Navigation coordinator -- Back pops, Restore pushes the confirm route.
    @State private var coordinator: WindowsHomeCoordinator
    /// The archived apps model. Observed via `@State` so the view redraws when
    /// the model's `@Published` properties change. The same instance is shared
    /// with the restore confirmation view via the RootView's
    /// `ArchivedAppsModelCache`.
    @State private var model: WindowsArchivedAppsModel

    init(
        accountId: String,
        coordinator: WindowsHomeCoordinator,
        model: WindowsArchivedAppsModel
    ) {
        self.accountId = accountId
        _coordinator = State(wrappedValue: coordinator)
        _model = State(wrappedValue: model)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                toolbar
                syncErrorBanner
                content
                Spacer()
            }
            .padding(16)
            .frame(maxWidth: 860)
        }
        .task {
            await model.loadArchivedApps()
        }
    }

    // MARK: - Toolbar (back + title + Refresh)

    /// Header: "< Back" on the left, "Archived Apps" title, and a Refresh
    /// button on the right. Refresh reloads from storage (TC-070: explicit
    /// button, NO pull-to-refresh).
    private var toolbar: some View {
        VStack(spacing: 12) {
            HStack {
                WindowsBackButtonView(onBack: { coordinator.pop() })
                Spacer()
                Button("Refresh") {
                    Task {
                        await model.loadArchivedApps()
                    }
                }
            }
            HStack {
                Text("Archived Apps")
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
            }
        }
    }

    // MARK: - Sync Error Banner

    /// Inline error banner shown when a persistence operation fails. Uses the
    /// InfoBar convention (4px colored left border + message).
    @ViewBuilder
    private var syncErrorBanner: some View {
        if let error = model.syncError {
            HStack(spacing: 0) {
                Rectangle()
                    .fill(Color.orange)
                    .frame(width: 4)
                    .cornerRadius(8)

                HStack(spacing: 8) {
                    Text(error)
                        .foregroundColor(.orange)
                    Spacer()
                }
                .padding(12)
            }
            .background(Color(white: 0.94))
            .cornerRadius(8)
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if model.isLoading && model.archivedApps.isEmpty {
            loadingState
        } else if model.isEmpty {
            emptyState
        } else {
            populatedState
        }
    }

    // MARK: - Loading State

    private var loadingState: some View {
        HStack(spacing: 8) {
            ProgressView()
            Text("Loading archived apps...")
                .foregroundColor(.gray)
            Spacer()
        }
    }

    // MARK: - Empty State (AC-W04-5)

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Text("( * )")
                .font(.title2)
                .foregroundColor(.gray)
            Text("No Archived Apps")
                .font(.title2)
                .fontWeight(.semibold)
            Text("Apps you archive will appear here. Use Refresh to reload.")
                .foregroundColor(.gray)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Populated State

    @ViewBuilder
    private var populatedState: some View {
        WindowsSectionHeader(title: "Archived")
        ForEach(model.archivedApps, id: \.id) { app in
            archivedAppRow(app)
        }
    }

    // MARK: - Archived App Row + Restore Flow

    /// A single archived app row with a Restore button. Tapping Restore sets
    /// the restore intent on the model and pushes the confirmation route.
    private func archivedAppRow(_ app: AppModel) -> some View {
        HStack(spacing: 12) {
            // App icon fallback glyph (no remote image loading in SwiftCrossUI)
            Text(iconGlyph(for: app))
                .font(.title3)
                .frame(width: 36, height: 36)
                .background(Color.gray.opacity(0.10))
                .cornerRadius(8)

            // App name + version
            VStack(alignment: .leading, spacing: 2) {
                Text(app.name)
                    .fontWeight(.medium)

                if let version = app.versionString, !version.isEmpty {
                    Text("v\(version)")
                        .foregroundColor(.gray)
                }
            }

            Spacer()

            // Colored status badge (if available)
            if let state = app.appStoreState {
                WindowsStatusBadge(state: state)
            }

            // Restore button (AC-W04-4: pushes confirmation route)
            Button("Restore") {
                model.restoreApp(appId: app.id)
                coordinator.push(
                    .restoreAppConfirm(
                        appId: app.id,
                        appName: app.name
                    )
                )
            }
            .foregroundColor(.blue)
        }
        .padding(12)
        .background(Color(white: 0.97))
        .cornerRadius(8)
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.gray.opacity(0.3), style: StrokeStyle(width: 1.0))
        }
    }

    // MARK: - Icon Glyph Fallback

    /// A graceful fallback when no remote icon is available. Uses the first
    /// letter of the app name (uppercased), or a generic app glyph.
    private func iconGlyph(for app: AppModel) -> String {
        if let first = app.name.first {
            return String(first).uppercased()
        }
        return "\u{25A0}" // filled square as generic app glyph
    }
}
