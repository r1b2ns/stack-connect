import SwiftUI

// MARK: - Factory

@MainActor
struct UserDetailViewFactory {
    static func build(user: UserModel) -> some View {
        UserDetailEntry(user: user)
    }
}

// MARK: - Entry

private struct UserDetailEntry: View {
    let user: UserModel

    @StateObject private var coordinator = UserDetailCoordinator()
    @StateObject private var viewModel: UserDetailViewModel

    init(user: UserModel) {
        self.user = user
        _viewModel = StateObject(wrappedValue: UserDetailViewModel(user: user))
    }

    var body: some View {
        UserDetailView(viewModel: viewModel)
            .environmentObject(coordinator)
    }
}

// MARK: - View

struct UserDetailView<ViewModel: UserDetailViewModelProtocol>: View {

    @ObservedObject var viewModel: ViewModel

    private var user: UserModel { viewModel.uiState.user }

    var body: some View {
        List {
            buildHeaderSection()
            buildRolesSection()
            buildAccessSection()
            buildInvitationSection()
        }
        .navigationTitle(user.displayName)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Header

    private func buildHeaderSection() -> some View {
        Section {
            HStack(spacing: 16) {
                buildAvatar()

                VStack(alignment: .leading, spacing: 4) {
                    Text(user.displayName)
                        .font(.title3)
                        .fontWeight(.semibold)

                    if let email = user.email {
                        Text(email)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if user.isPending {
                        buildPendingBadge()
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func buildPendingBadge() -> some View {
        Text(String(localized: "Pending"))
            .font(.caption2)
            .fontWeight(.medium)
            .foregroundStyle(.orange)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.orange.opacity(0.12))
            .clipShape(Capsule())
            .padding(.top, 2)
    }

    private func buildAvatar() -> some View {
        let initials = [user.firstName?.prefix(1), user.lastName?.prefix(1)]
            .compactMap { $0.map(String.init) }
            .joined()

        return ZStack {
            Circle()
                .fill(Color.blue.opacity(0.15))

            if initials.isEmpty {
                Image(systemName: "person.fill")
                    .foregroundStyle(.blue)
                    .font(.title3)
            } else {
                Text(initials)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.blue)
            }
        }
        .frame(width: 56, height: 56)
    }

    // MARK: - Roles

    @ViewBuilder
    private func buildRolesSection() -> some View {
        Section {
            if user.roles.isEmpty {
                Text("—")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(user.roles, id: \.self) { role in
                    Text(UserModel.formatRole(role))
                }
            }
        } header: {
            Text("Roles")
        }
    }

    // MARK: - Access

    private func buildAccessSection() -> some View {
        Section {
            buildAccessRow(
                title: String(localized: "Access to All Apps"),
                isOn: user.allAppsVisible
            )
            buildAccessRow(
                title: String(localized: "Provisioning Allowed"),
                isOn: user.provisioningAllowed
            )
        } header: {
            Text("Access")
        }
    }

    private func buildAccessRow(title: String, isOn: Bool) -> some View {
        HStack {
            Text(title)

            Spacer()

            Image(systemName: isOn ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(isOn ? .green : .secondary)
        }
    }

    // MARK: - Invitation

    @ViewBuilder
    private func buildInvitationSection() -> some View {
        if user.isPending {
            Section {
                HStack {
                    Text(String(localized: "Invitation Expires"))

                    Spacer()

                    if let expirationDate = user.expirationDate {
                        Text(expirationDate.formatted(date: .abbreviated, time: .shortened))
                            .foregroundStyle(.secondary)
                    } else {
                        Text("—")
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Invitation")
            }
        }
    }
}
