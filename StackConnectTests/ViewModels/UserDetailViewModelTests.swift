import XCTest
import StackCoreRust
import StackProtocols
@testable import StackConnect

@MainActor
final class UserDetailViewModelTests: XCTestCase {

    // MARK: - Mock seam

    /// In-memory `UserManaging` stub. Records calls and lets each method be armed
    /// with either a success value or a thrown error, so the ViewModel's edit /
    /// delete / visible-apps logic can be exercised without the network or keychain.
    private final class MockUserManaging: UserManaging, @unchecked Sendable {

        // Arm-able outcomes
        var updateUserError: Error?
        var visibleAppsToReturn: [String] = []
        var fetchVisibleAppsError: Error?
        var updateVisibleAppsError: Error?
        var deleteError: Error?
        var appsToReturn: [StackProtocols.AppInfo] = []
        var fetchAppsError: Error?

        // Recorded calls
        private(set) var updateUserCalls: [(id: String, roles: [String], allApps: Bool, provisioning: Bool)] = []
        private(set) var updateVisibleAppsCalls: [(id: String, appIds: [String])] = []
        private(set) var deleteCalls: [(id: String, isPending: Bool)] = []
        private(set) var fetchVisibleAppsCallCount = 0
        private(set) var fetchAppsCallCount = 0

        func updateUser(id: String, roles: [String], allAppsVisible: Bool, provisioningAllowed: Bool) async throws {
            updateUserCalls.append((id, roles, allAppsVisible, provisioningAllowed))
            if let updateUserError { throw updateUserError }
        }

        func fetchUserVisibleApps(id: String) async throws -> [String] {
            fetchVisibleAppsCallCount += 1
            if let fetchVisibleAppsError { throw fetchVisibleAppsError }
            return visibleAppsToReturn
        }

        func updateUserVisibleApps(id: String, appIds: [String]) async throws {
            updateVisibleAppsCalls.append((id, appIds))
            if let updateVisibleAppsError { throw updateVisibleAppsError }
        }

        func deleteUser(id: String, isPending: Bool) async throws {
            deleteCalls.append((id, isPending))
            if let deleteError { throw deleteError }
        }

        func fetchApps() async throws -> [StackProtocols.AppInfo] {
            fetchAppsCallCount += 1
            if let fetchAppsError { throw fetchAppsError }
            return appsToReturn
        }
    }

    // MARK: - Fixtures

    private func makeAccount() -> AccountModel {
        AccountModel(
            id: "acc-1",
            name: "Test Team",
            providerType: .apple
        )
    }

    private func makeUser(
        id: String = "user-1",
        roles: [String] = ["DEVELOPER"],
        allAppsVisible: Bool = false,
        provisioningAllowed: Bool = true,
        isPending: Bool = false,
        expirationDate: Date? = nil
    ) -> UserModel {
        UserModel(
            id: id,
            firstName: "Alan",
            lastName: "Turing",
            email: "alan@example.com",
            roles: roles,
            allAppsVisible: allAppsVisible,
            provisioningAllowed: provisioningAllowed,
            isPending: isPending,
            expirationDate: expirationDate
        )
    }

    private func makeSUT(
        user: UserModel,
        service: MockUserManaging
    ) -> UserDetailViewModel {
        UserDetailViewModel(
            user: user,
            account: makeAccount(),
            keychain: MockKeyStorable(),
            service: service
        )
    }

    /// Builds a `StackError.Http` 403 carrying the `FORBIDDEN_ERROR` JSON:API code
    /// so `AppleAPIErrorTranslator.isForbidden` returns true.
    private func forbiddenError() -> Error {
        let body = "{\"errors\":[{\"status\":\"403\",\"code\":\"FORBIDDEN_ERROR\",\"title\":\"\",\"detail\":\"\"}]}"
        return StackCoreRust.StackError.Http(status: 403, message: body)
    }

    // MARK: - Existing coverage (kept green)

    func testPendingUserExposesExpirationDateAndRoles() {
        let expiration = Date(timeIntervalSince1970: 1_700_000_000)
        let user = makeUser(
            id: "invitation-1",
            roles: ["ADMIN", "DEVELOPER", "FINANCE"],
            allAppsVisible: true,
            provisioningAllowed: false,
            isPending: true,
            expirationDate: expiration
        )

        let sut = makeSUT(user: user, service: MockUserManaging())

        XCTAssertEqual(sut.uiState.user.roles.count, 3)
        XCTAssertTrue(sut.uiState.user.isPending)
        XCTAssertEqual(sut.uiState.user.expirationDate, expiration)
    }

    func testActiveUserHasNoExpirationDateAndIsNotPending() {
        let user = makeUser(roles: ["DEVELOPER"], allAppsVisible: false, provisioningAllowed: true)

        let sut = makeSUT(user: user, service: MockUserManaging())

        XCTAssertFalse(sut.uiState.user.isPending)
        XCTAssertNil(sut.uiState.user.expirationDate)
        XCTAssertEqual(sut.uiState.user.roles, ["DEVELOPER"])
    }

    // MARK: - Init splits roles into primary + resources

    func testInitSplitsRolesIntoPrimaryAndResources() {
        let user = makeUser(roles: ["APP_MANAGER", "CREATE_APPS", "GENERATE_INDIVIDUAL_KEYS"])

        let sut = makeSUT(user: user, service: MockUserManaging())

        XCTAssertEqual(sut.uiState.selectedPrimaryRole, "APP_MANAGER")
        XCTAssertEqual(sut.uiState.selectedResources, ["CREATE_APPS", "GENERATE_INDIVIDUAL_KEYS"])
    }

    // MARK: - Save role: success

    func testSaveRoleSuccessUpdatesUiStateAndToast() async {
        let mock = MockUserManaging()
        let sut = makeSUT(user: makeUser(roles: ["DEVELOPER"]), service: mock)
        sut.uiState.showRoleEditor = true
        sut.uiState.selectedPrimaryRole = "ADMIN"

        let ok = await sut.saveRole()

        XCTAssertTrue(ok)
        XCTAssertEqual(mock.updateUserCalls.count, 1)
        XCTAssertEqual(mock.updateUserCalls.first?.roles, ["ADMIN"])
        XCTAssertEqual(sut.uiState.user.roles, ["ADMIN"])
        XCTAssertFalse(sut.uiState.showRoleEditor)
        XCTAssertNotNil(sut.uiState.toastMessage)
        XCTAssertNil(sut.uiState.errorMessage)
        XCTAssertFalse(sut.uiState.isSaving)
    }

    func testSaveRoleComposesPrimaryPlusResources() async {
        let mock = MockUserManaging()
        let sut = makeSUT(user: makeUser(roles: ["DEVELOPER", "CREATE_APPS"]), service: mock)
        sut.uiState.selectedPrimaryRole = "APP_MANAGER"
        sut.uiState.selectedResources = ["CREATE_APPS"]

        let ok = await sut.saveRole()

        XCTAssertTrue(ok)
        // Primary first, then catalog-ordered resources.
        XCTAssertEqual(mock.updateUserCalls.first?.roles, ["APP_MANAGER", "CREATE_APPS"])
    }

    // MARK: - Save role: 403 surfaces the admin-permission error

    func testSaveRoleForbiddenSurfacesAdminPermissionError() async {
        let mock = MockUserManaging()
        mock.updateUserError = forbiddenError()
        let sut = makeSUT(user: makeUser(roles: ["DEVELOPER"]), service: mock)
        sut.uiState.selectedPrimaryRole = "ADMIN"

        let ok = await sut.saveRole()

        XCTAssertFalse(ok)
        XCTAssertNotNil(sut.uiState.errorMessage)
        XCTAssertTrue(sut.uiState.errorMessage?.contains("Admin role") ?? false)
        // Optimistic update must NOT have happened on failure.
        XCTAssertEqual(sut.uiState.user.roles, ["DEVELOPER"])
        XCTAssertFalse(sut.uiState.isSaving)
    }

    // MARK: - Save resources & flags

    func testSaveResourcesUpdatesFlagsAndKeepsPrimaryRole() async {
        let mock = MockUserManaging()
        let sut = makeSUT(
            user: makeUser(roles: ["DEVELOPER"], allAppsVisible: true, provisioningAllowed: false),
            service: mock
        )
        sut.uiState.selectedResources = ["CREATE_APPS"]
        sut.uiState.allAppsVisible = false
        sut.uiState.provisioningAllowed = true

        let ok = await sut.saveResources()

        XCTAssertTrue(ok)
        let call = mock.updateUserCalls.first
        XCTAssertEqual(call?.roles, ["DEVELOPER", "CREATE_APPS"])
        XCTAssertEqual(call?.allApps, false)
        XCTAssertEqual(call?.provisioning, true)
        XCTAssertFalse(sut.uiState.user.allAppsVisible)
        XCTAssertTrue(sut.uiState.user.provisioningAllowed)
    }

    // MARK: - Visible apps: load + save (full replace)

    func testLoadVisibleAppsPopulatesAppsAndSelection() async {
        let mock = MockUserManaging()
        mock.appsToReturn = [
            AppInfo(id: "app-2", name: "Zeta", bundleId: "com.z"),
            AppInfo(id: "app-1", name: "Alpha", bundleId: "com.a"),
        ]
        mock.visibleAppsToReturn = ["app-1"]
        let sut = makeSUT(user: makeUser(allAppsVisible: false), service: mock)

        await sut.loadVisibleApps()

        XCTAssertEqual(mock.fetchAppsCallCount, 1)
        XCTAssertEqual(mock.fetchVisibleAppsCallCount, 1)
        // Sorted by name.
        XCTAssertEqual(sut.uiState.availableApps.map(\.id), ["app-1", "app-2"])
        XCTAssertEqual(sut.uiState.selectedAppIds, ["app-1"])
        XCTAssertTrue(sut.uiState.visibleAppsLoaded)
        XCTAssertFalse(sut.uiState.isLoadingVisibleApps)
    }

    func testLoadVisibleAppsSkippedWhenAllAppsVisible() async {
        let mock = MockUserManaging()
        let sut = makeSUT(user: makeUser(allAppsVisible: true), service: mock)

        await sut.loadVisibleApps()

        XCTAssertEqual(mock.fetchAppsCallCount, 0)
        XCTAssertEqual(mock.fetchVisibleAppsCallCount, 0)
        XCTAssertFalse(sut.uiState.canEditVisibleApps)
    }

    func testSaveVisibleAppsSendsFullSelectionSet() async {
        let mock = MockUserManaging()
        let sut = makeSUT(user: makeUser(allAppsVisible: false), service: mock)
        sut.uiState.selectedAppIds = ["app-1", "app-3"]

        let ok = await sut.saveVisibleApps()

        XCTAssertTrue(ok)
        XCTAssertEqual(mock.updateVisibleAppsCalls.count, 1)
        XCTAssertEqual(Set(mock.updateVisibleAppsCalls.first?.appIds ?? []), ["app-1", "app-3"])
        XCTAssertFalse(sut.uiState.showVisibleAppsEditor)
        XCTAssertNotNil(sut.uiState.toastMessage)
    }

    func testSaveVisibleAppsEmptySelectionClearsScoping() async {
        let mock = MockUserManaging()
        let sut = makeSUT(user: makeUser(allAppsVisible: false), service: mock)
        sut.uiState.selectedAppIds = []

        let ok = await sut.saveVisibleApps()

        XCTAssertTrue(ok)
        // Full replace with an empty array clears all scoping.
        XCTAssertEqual(mock.updateVisibleAppsCalls.first?.appIds, [])
    }

    // MARK: - Delete: success signals dismissal

    func testDeleteActiveUserSuccessReturnsTrue() async {
        let mock = MockUserManaging()
        let sut = makeSUT(user: makeUser(id: "user-9", isPending: false), service: mock)

        let ok = await sut.deleteUser()

        XCTAssertTrue(ok) // View pops back on true.
        XCTAssertEqual(mock.deleteCalls.count, 1)
        XCTAssertEqual(mock.deleteCalls.first?.id, "user-9")
        XCTAssertEqual(mock.deleteCalls.first?.isPending, false)
        XCTAssertFalse(sut.uiState.isSaving)
    }

    func testDeletePendingUserPassesIsPendingTrue() async {
        let mock = MockUserManaging()
        let sut = makeSUT(user: makeUser(id: "inv-1", roles: ["DEVELOPER"], isPending: true), service: mock)

        let ok = await sut.deleteUser()

        XCTAssertTrue(ok)
        XCTAssertEqual(mock.deleteCalls.first?.isPending, true)
    }

    func testDeleteForbiddenSurfacesAdminPermissionError() async {
        let mock = MockUserManaging()
        mock.deleteError = forbiddenError()
        let sut = makeSUT(user: makeUser(), service: mock)

        let ok = await sut.deleteUser()

        XCTAssertFalse(ok)
        XCTAssertNotNil(sut.uiState.errorMessage)
        XCTAssertTrue(sut.uiState.errorMessage?.contains("Admin role") ?? false)
    }

    // MARK: - Guards: pending → edits disabled

    func testPendingUserDisablesEditsButAllowsDelete() {
        let sut = makeSUT(user: makeUser(isPending: true), service: MockUserManaging())

        XCTAssertFalse(sut.uiState.canEdit)
        XCTAssertFalse(sut.uiState.canEditRole)
        XCTAssertFalse(sut.uiState.canEditVisibleApps)
        XCTAssertTrue(sut.uiState.canDelete)
    }

    func testSaveRoleNoOpForPendingUser() async {
        let mock = MockUserManaging()
        let sut = makeSUT(user: makeUser(roles: ["DEVELOPER"], isPending: true), service: mock)
        sut.uiState.selectedPrimaryRole = "ADMIN"

        let ok = await sut.saveRole()

        XCTAssertFalse(ok)
        XCTAssertTrue(mock.updateUserCalls.isEmpty)
    }

    // MARK: - Guards: account holder → delete/role disabled

    func testAccountHolderDisablesDeleteAndRoleEditing() {
        let sut = makeSUT(user: makeUser(roles: ["ACCOUNT_HOLDER"]), service: MockUserManaging())

        XCTAssertTrue(sut.uiState.isAccountHolder)
        XCTAssertFalse(sut.uiState.canEditRole)
        XCTAssertFalse(sut.uiState.canDelete)
    }

    func testSaveRoleNoOpForAccountHolder() async {
        let mock = MockUserManaging()
        let sut = makeSUT(user: makeUser(roles: ["ACCOUNT_HOLDER"]), service: mock)
        sut.uiState.selectedPrimaryRole = "ADMIN"

        let ok = await sut.saveRole()

        XCTAssertFalse(ok)
        XCTAssertTrue(mock.updateUserCalls.isEmpty)
    }

    func testDeleteNoOpForAccountHolder() async {
        let mock = MockUserManaging()
        let sut = makeSUT(user: makeUser(roles: ["ACCOUNT_HOLDER"]), service: mock)

        let ok = await sut.deleteUser()

        XCTAssertFalse(ok)
        XCTAssertTrue(mock.deleteCalls.isEmpty)
    }

    // MARK: - Role → add-ons gating (Defect A)

    /// Switching to a non-app-management role must drop selected add-ons and force
    /// `provisioningAllowed = false`, so an invalid combination can't be submitted.
    func testSelectNonAppRoleClearsResourcesAndForcesProvisioningOff() {
        let sut = makeSUT(
            user: makeUser(roles: ["DEVELOPER", "CREATE_APPS"], provisioningAllowed: true),
            service: MockUserManaging()
        )
        // Start from a valid Developer selection with add-ons + provisioning.
        sut.uiState.selectedResources = ["CREATE_APPS", "GENERATE_INDIVIDUAL_KEYS"]
        sut.uiState.provisioningAllowed = true

        sut.selectPrimaryRole("ADMIN")

        XCTAssertEqual(sut.uiState.selectedPrimaryRole, "ADMIN")
        XCTAssertTrue(sut.uiState.selectedResources.isEmpty)
        XCTAssertFalse(sut.uiState.provisioningAllowed)
    }

    /// Marketing keeps only CREATE_APPS and loses provisioning + individual keys.
    func testSelectMarketingKeepsOnlyCreateAppsAndDropsProvisioning() {
        let sut = makeSUT(
            user: makeUser(roles: ["DEVELOPER"], provisioningAllowed: true),
            service: MockUserManaging()
        )
        sut.uiState.selectedResources = ["CREATE_APPS", "GENERATE_INDIVIDUAL_KEYS"]
        sut.uiState.provisioningAllowed = true

        sut.selectPrimaryRole("MARKETING")

        XCTAssertEqual(sut.uiState.selectedResources, ["CREATE_APPS"])
        XCTAssertFalse(sut.uiState.provisioningAllowed)
    }

    /// Switching between two app-management roles that share the same add-on set
    /// keeps the valid selection intact.
    func testSelectAppManagerFromDeveloperKeepsSharedResources() {
        let sut = makeSUT(user: makeUser(roles: ["DEVELOPER"]), service: MockUserManaging())
        sut.uiState.selectedResources = ["CREATE_APPS", "GENERATE_INDIVIDUAL_KEYS"]
        sut.uiState.provisioningAllowed = true

        sut.selectPrimaryRole("APP_MANAGER")

        XCTAssertEqual(sut.uiState.selectedResources, ["CREATE_APPS", "GENERATE_INDIVIDUAL_KEYS"])
        XCTAssertTrue(sut.uiState.provisioningAllowed)
    }

    // MARK: - compose() never emits invalid add-ons or cloud-managed roles

    func testComposeNeverEmitsInvalidAddOnForAnyBaseRole() {
        // For every assignable base role, feeding *all* possible add-ons must only
        // ever yield add-ons allowed for that role — and never a cloud-managed one.
        let allAddOns: Set<String> = [
            "CREATE_APPS",
            "GENERATE_INDIVIDUAL_KEYS",
            "CLOUD_MANAGED_APP_DISTRIBUTION",
            "CLOUD_MANAGED_DEVELOPER_ID",
        ]
        let cloudManaged = Set(UserRoleCatalog.cloudManagedRoles)

        for role in UserRoleCatalog.assignablePrimaryRoles {
            let composed = UserRoleCatalog.compose(primary: role, resources: allAddOns)
            let allowed = Set(UserRoleCatalog.allowedResources(for: role))
            let emittedAddOns = Set(composed.filter { $0 != role }).subtracting(cloudManaged)

            // Base role is always first.
            XCTAssertEqual(composed.first, role, "\(role) should be the base role")
            // Emitted add-ons are a subset of what's allowed for the role.
            XCTAssertTrue(emittedAddOns.isSubset(of: allowed), "\(role) emitted invalid add-ons: \(emittedAddOns)")
            // Cloud-managed roles are never emitted from a fresh selection.
            XCTAssertTrue(Set(composed).isDisjoint(with: cloudManaged), "\(role) emitted a cloud-managed role")
        }
    }

    func testComposeDropsAddOnsForNonAppRole() {
        let composed = UserRoleCatalog.compose(
            primary: "ADMIN",
            resources: ["CREATE_APPS", "GENERATE_INDIVIDUAL_KEYS"]
        )
        XCTAssertEqual(composed, ["ADMIN"])
    }

    // MARK: - READ_ONLY round-trips

    func testReadOnlyUserRoundTripsThroughSplitAndCompose() {
        let (primary, resources) = UserRoleCatalog.split(["READ_ONLY"])
        XCTAssertEqual(primary, "READ_ONLY")
        XCTAssertTrue(resources.isEmpty)

        let composed = UserRoleCatalog.compose(primary: primary, resources: resources)
        XCTAssertEqual(composed, ["READ_ONLY"])
    }

    func testReadOnlyUserInitAndSaveKeepsBaseRole() async {
        let mock = MockUserManaging()
        let sut = makeSUT(user: makeUser(roles: ["READ_ONLY"], provisioningAllowed: false), service: mock)

        XCTAssertEqual(sut.uiState.selectedPrimaryRole, "READ_ONLY")
        XCTAssertTrue(sut.uiState.selectedResources.isEmpty)

        let ok = await sut.saveResources()

        XCTAssertTrue(ok)
        XCTAssertEqual(mock.updateUserCalls.first?.roles, ["READ_ONLY"])
        XCTAssertEqual(mock.updateUserCalls.first?.provisioning, false)
    }

    // MARK: - Cloud-managed role preservation on save

    /// A user who already has an auto-assigned cloud-managed role keeps it when
    /// saving resources/flags with the base role unchanged.
    func testSaveResourcesPreservesCloudManagedRoleWhenBaseUnchanged() async {
        let mock = MockUserManaging()
        let sut = makeSUT(
            user: makeUser(roles: ["DEVELOPER", "CLOUD_MANAGED_APP_DISTRIBUTION"]),
            service: mock
        )
        // Base role stays DEVELOPER; user toggles an add-on.
        sut.uiState.selectedResources = ["CREATE_APPS"]

        let ok = await sut.saveResources()

        XCTAssertTrue(ok)
        let roles = mock.updateUserCalls.first?.roles ?? []
        XCTAssertTrue(roles.contains("DEVELOPER"))
        XCTAssertTrue(roles.contains("CREATE_APPS"))
        XCTAssertTrue(roles.contains("CLOUD_MANAGED_APP_DISTRIBUTION"), "cloud-managed role should be preserved")
    }

    /// Changing the base role drops the previously auto-assigned cloud-managed role.
    func testSaveRoleChangeDropsCloudManagedRole() async {
        let mock = MockUserManaging()
        let sut = makeSUT(
            user: makeUser(roles: ["DEVELOPER", "CLOUD_MANAGED_APP_DISTRIBUTION"]),
            service: mock
        )
        sut.selectPrimaryRole("ADMIN")

        let ok = await sut.saveRole()

        XCTAssertTrue(ok)
        XCTAssertEqual(mock.updateUserCalls.first?.roles, ["ADMIN"], "cloud-managed role must be dropped on role change")
    }

    // MARK: - Error surfacing (Defect B)

    /// A rejected save whose body is the real "provisioning privilege" 409 must
    /// surface Apple's exact message — not the generic "Failed to update user".
    func testSaveResourcesSurfacesAppleProvisioning409Message() async {
        let detail = "The user can't have provisioning privilege."
        let body = "{\"errors\":[{\"status\":\"409\",\"code\":\"ENTITY_ERROR.ATTRIBUTE.INVALID\",\"title\":\"\",\"detail\":\"\(detail)\"}]}"
        let mock = MockUserManaging()
        mock.updateUserError = StackCoreRust.StackError.Http(status: 409, message: body)
        let sut = makeSUT(user: makeUser(roles: ["DEVELOPER"]), service: mock)

        let ok = await sut.saveResources()

        XCTAssertFalse(ok)
        XCTAssertEqual(sut.uiState.errorMessage, detail)
    }
}
