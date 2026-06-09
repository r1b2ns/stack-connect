import SwiftCrossUI
import WindowsAppCore

// T-W08 — Users tab content for the Apps List screen.
//
// Displays the account's team members (active users + pending invitations)
// fetched live via `WindowsUsersListModel`. Each row shows the user's
// display name (bold) and primary role (gray). There is no per-row
// navigation in v1 (tapping a user row does nothing / pushes no route).
//
// States: loading (ProgressView + text), empty ("No Users" + helper text),
// error (inline banner matching the syncErrorBanner convention), and
// populated (user rows).
//
// Layout follows the Windows app row/state styling conventions from
// `WindowsArchivedAppsView` / `WindowsAppRow`. SwiftCrossUI constraints:
// NO `.sheet`, NO `.alert`, NO SF Symbols (text/emoji glyphs), NO
// pull-to-refresh.

struct WindowsUsersTabView: View {

    @State private var model: WindowsUsersListModel
    @State private var hasLoaded: Bool = false

    init(model: WindowsUsersListModel) {
        _model = State(wrappedValue: model)
        _hasLoaded = State(wrappedValue: false)
    }

    var body: some View {
        VStack(spacing: 16) {
            syncErrorBanner
            content
        }
        .task {
            guard !hasLoaded else { return }
            hasLoaded = true
            await model.loadUsers()
        }
    }

    // MARK: - Sync Error Banner

    /// Inline error banner shown when a fetch fails. Uses the InfoBar
    /// convention (4px colored left border + message). Mirrors the pattern
    /// in `WindowsAppsListView` and `WindowsArchivedAppsView`.
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
        if model.isLoading && model.users.isEmpty {
            loadingState
        } else if model.isEmpty {
            emptyState
        } else {
            populatedState
        }
    }

    // MARK: - Loading State (AC-W05-4)

    private var loadingState: some View {
        HStack(spacing: 8) {
            ProgressView()
            Text("Loading users...")
                .foregroundColor(.gray)
            Spacer()
        }
    }

    // MARK: - Empty State (AC-W05-5)

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Text("( * )")
                .font(.title2)
                .foregroundColor(.gray)
            Text("No Users")
                .font(.title2)
                .fontWeight(.semibold)
            Text("This account has no team members. Users will appear here once added in App Store Connect.")
                .foregroundColor(.gray)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Populated State (AC-W05-2)

    @ViewBuilder
    private var populatedState: some View {
        WindowsSectionHeader(title: "Team Members")
        ForEach(model.users, id: \.id) { user in
            userRow(user)
        }
    }

    // MARK: - User Row

    /// A single user row displaying the user's name (bold) and primary role
    /// (gray). No chevron, no tap action (AC-W05-2: no per-row navigation
    /// in v1).
    private func userRow(_ user: UserModel) -> some View {
        HStack(spacing: 12) {
            // User avatar fallback glyph (first letter of display name)
            Text(avatarGlyph(for: user))
                .font(.title3)
                .frame(width: 36, height: 36)
                .background(Color.blue.opacity(0.10))
                .cornerRadius(18)

            // Name + role
            VStack(alignment: .leading, spacing: 2) {
                Text(user.displayName)
                    .fontWeight(.bold)

                Text(user.primaryRoleDisplayName)
                    .foregroundColor(.gray)
            }

            Spacer()

            // Pending badge (if applicable)
            if user.isPending {
                Text("Pending")
                    .foregroundColor(.orange)
                    .fontWeight(.medium)
            }
        }
        .padding(12)
        .background(Color(white: 0.97))
        .cornerRadius(8)
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.gray.opacity(0.3), style: StrokeStyle(width: 1.0))
        }
    }

    // MARK: - Avatar Glyph Fallback

    /// A graceful fallback avatar. Uses the first letter of the display name
    /// (uppercased), or a generic person glyph.
    private func avatarGlyph(for user: UserModel) -> String {
        if let first = user.displayName.first, first != "\u{2013}" {
            return String(first).uppercased()
        }
        return "\u{25CF}" // filled circle as generic person glyph
    }
}
