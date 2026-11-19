import Foundation

/// Works out the `AccountRole` of an account added with "Sign in with Apple
/// ID" from the signed-in user's App Store Connect roles (plan
/// `apple-id-sign-in.md` 3.2, Permissions), instead of an API key's role
/// picked by hand.
protocol AppleSessionRoleResolving: Sendable {
    /// The role of `appleId` in `team`, or `.unspecified` when it can't be
    /// read (the user may not see the team's users). Never throws: the role
    /// is a label, App Store Connect enforces the real permissions.
    func role(of appleId: String, in team: AppleWebSessionReference) async -> AccountRole
}

/// Reads the team's users through the session (`GET iris/v1/users`, the
/// core's Users capability) and picks the signed-in user's primary role.
struct AppleSessionRoleResolver: AppleSessionRoleResolving {

    /// Builds the session connection of a team. Injected for tests.
    var makeUsersFetcher: @Sendable (AppleCredentials) -> any TeamUsersFetching = { AppleAccountConnection(credentials: $0) }

    func role(of appleId: String, in team: AppleWebSessionReference) async -> AccountRole {
        let fetcher = makeUsersFetcher(AppleCredentials(webSession: team))
        do {
            let users = try await fetcher.fetchUsers()
            let id = AppleSessionKeychainStore.normalized(appleId)
            guard let me = users.first(where: { $0.email.map(AppleSessionKeychainStore.normalized) == id }) else {
                Log.print.info("[AppleSession] The signed-in user isn't in the team's user list; role left unspecified")
                return .unspecified
            }
            return AccountRole.primary(fromAppStoreConnectRoles: me.roles)
        } catch {
            Log.print.info("[AppleSession] Couldn't read the team's users for the role: \(error.localizedDescription, privacy: .public)")
            return .unspecified
        }
    }
}

extension AccountRole {

    /// The most capable of App Store Connect's role values (`ADMIN`,
    /// `APP_MANAGER`, …) as an `AccountRole`; the Account Holder counts as
    /// Admin. `.unspecified` when none is known.
    static func primary(fromAppStoreConnectRoles roles: [String]) -> AccountRole {
        let ranked: [(String, AccountRole)] = [
            ("ACCOUNT_HOLDER", .admin),
            ("ADMIN", .admin),
            ("APP_MANAGER", .appManager),
            ("DEVELOPER", .developer),
            ("MARKETING", .marketing),
            ("FINANCE", .finance),
            ("SALES", .sales),
            ("CUSTOMER_SUPPORT", .customerSupport)
        ]
        let upper = Set(roles.map { $0.uppercased() })
        return ranked.first { upper.contains($0.0) }?.1 ?? .unspecified
    }
}
