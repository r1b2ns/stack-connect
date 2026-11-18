import SwiftUI

/// Middle column of an account item: the existing list screen of the section,
/// built by its own factory. Rows picked here open in the detail column (the
/// environment `HomeCoordinator` is the split view's content coordinator).
struct RootAccountContentView: View {

    let account: AccountModel
    let section: RootAccountSection

    var body: some View {
        if account.isExpired {
            buildExpired()
        } else {
            buildSection()
        }
    }

    @ViewBuilder
    private func buildSection() -> some View {
        switch section {
        case .apps:
            switch account.providerType {
            case .apple:
                AppListViewFactory.build(account: account, showsUsersTab: false)
            case .googlePlay:
                GooglePlayAppListViewFactory.build(account: account)
            case .firebase:
                FirebaseProjectListViewFactory.build(account: account)
            }
        case .users:
            UserAccessViewFactory.build(account: account)
        case .devices:
            DevicesListViewFactory.build(account: account)
        case .certificates:
            CertificatesListViewFactory.build(account: account)
        case .identifiers:
            IdentifiersListViewFactory.build(account: account)
        case .profiles:
            ProfilesListViewFactory.build(account: account)
        case .manage:
            AccountManagementViewFactory.build(account: account)
        }
    }

    /// Same rule as the Accounts list: an expired account stays locked until
    /// its file is imported again.
    private func buildExpired() -> some View {
        ContentUnavailableView {
            Label(String(localized: "Account Expired"), systemImage: "clock.badge.exclamationmark")
        } description: {
            Text("The account \"\(account.name)\" has expired. Re-import its file to keep using it.")
        } actions: {
            StackTrackedButton(String(localized: "Re-import File"), button: .reimport, on: .accountsList) {
                DeepLinkRouter.shared.open(DeepLink.reimport(accountId: account.id).url)
            }
            .buttonStyle(.borderedProminent)
        }
        .navigationTitle(account.name)
    }
}
