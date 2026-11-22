import SwiftUI

// Building blocks shared by the compact Home (`HomeView`, a List) and the
// regular-width Dashboard (`RootDashboardView`, a grid), so both roots show the
// same banners, alerts and share sheet from the same `HomeViewModel`.

// MARK: - Sync Banner

struct HomeSyncBanner: View {

    let syncState: SyncState

    var body: some View {
        if syncState.isSyncing {
            HStack(spacing: 10) {
                ProgressView()
                    .scaleEffect(0.75)

                Text(text)
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Spacer()
            }
            .padding(.vertical, 4)
            .listRowSeparator(.hidden)
        }
    }

    private var text: String {
        let count = syncState.accountsInProgress.count
        guard count > 0 else { return String(localized: "Syncing…") }
        // Both stores at once: say how many of each.
        let byProvider = syncState.inProgressCountByProvider
        if let appStore = byProvider[.apple], let googlePlay = byProvider[.googlePlay] {
            return String(
                localized: "Syncing \(count) account(s)… (\(appStore) App Store Connect, \(googlePlay) Google Play)",
                comment: "Home sync banner while App Store Connect and Google Play accounts sync together: total, then the count per store."
            )
        }
        return String(localized: "Syncing \(count) account(s)…")
    }
}

// MARK: - Pending Agreements Banners

struct HomeAgreementsBanners<ViewModel: HomeViewModelProtocol>: View {

    @ObservedObject var viewModel: ViewModel

    var body: some View {
        ForEach(viewModel.uiState.pendingAgreementsAccounts, id: \.id) { account in
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(String(localized: "Action Required: App Store Connect Agreements"))
                            .font(.subheadline)
                            .fontWeight(.semibold)

                        Text("Apple reported pending or updated agreements for \"\(account.name)\". Some data may be unavailable until you review and accept them.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 0)

                    Button {
                        viewModel.dismissPendingAgreements(accountId: account.id)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(String(localized: "Dismiss"))
                }

                HStack(spacing: 16) {
                    Link(destination: AppStoreConnectLinks.agreements) {
                        Text(String(localized: "Review Agreements"))
                            .font(.footnote)
                            .fontWeight(.semibold)
                    }
                    .trackOpenURL(.reviewAgreements, on: .home)

                    buildShareButton(for: account)
                }
            }
            .padding(.vertical, 8)
            .listRowSeparator(.hidden)
        }
    }

    /// Asks the ViewModel to look up the Account Holder and prepare the share
    /// payload; the share sheet itself is presented by `homePresentations` once
    /// `uiState.agreementShare` is set. Shows a spinner and stays disabled while
    /// that account's lookup is in flight.
    private func buildShareButton(for account: AccountModel) -> some View {
        let isPreparing = viewModel.uiState.preparingAgreementShareAccountIds.contains(account.id)
        return Button {
            Task { await viewModel.prepareAgreementShare(accountId: account.id) }
        } label: {
            ZStack {
                // Keeps the label's size stable while swapping icon and spinner.
                Image(systemName: "square.and.arrow.up")
                    .font(.footnote.weight(.semibold))
                    .opacity(isPreparing ? 0 : 1)

                if isPreparing {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .disabled(isPreparing)
        .accessibilityLabel(String(
            localized: "Share with Account Holder",
            comment: "Accessibility label of the Home agreements banner button that shares a request with the team's Account Holder."
        ))
        .accessibilityHint(String(
            localized: "Opens the share sheet with a message asking the team's Account Holder to accept the pending agreements.",
            comment: "Accessibility hint of the Home agreements banner button that shares a request with the team's Account Holder."
        ))
    }
}

// MARK: - Sign In Again Banner

/// "N accounts need you to sign in again": the accounts whose Apple ID session
/// or Google login expired (`uiState.expiredSignIns`). With one expired
/// sign-in its button starts that sign-in right away; with several it opens
/// the list (`HomeSignInAgainListView`). The close button hides it until the
/// next launch (rules in `HomeViewModel.dismissedSignInAccountIds`).
struct HomeSignInAgainBanner<ViewModel: HomeViewModelProtocol>: View {

    @ObservedObject var viewModel: ViewModel

    private var state: HomeUiState { viewModel.uiState }

    var body: some View {
        if state.showSignInAgainBanner, !state.expiredSignIns.isEmpty {
            StackBannerCard(
                systemImage: "person.crop.circle.badge.exclamationmark",
                tint: .orange,
                title: title,
                message: message,
                onDismiss: { viewModel.dismissSignInAgainBanner() }
            ) {
                buildActionButton()
            }
        }
    }

    private var single: ExpiredSignIn? {
        state.expiredSignIns.count == 1 ? state.expiredSignIns.first : nil
    }

    private var title: String {
        let count = state.expiredAccountCount
        if count == 1, let name = state.expiredSignIns.first?.accounts.first?.name {
            return String(localized: "\"\(name)\" needs you to sign in again",
                          comment: "Home banner title when one account's sign-in (Apple ID or Google) expired. The placeholder is the account name.")
        }
        return String(localized: "\(count) accounts need you to sign in again",
                      comment: "Home banner title when several accounts' sign-ins (Apple ID or Google) expired.")
    }

    private var message: String {
        guard let single else {
            return String(localized: "\(state.expiredSignIns.count) sign-ins expired or were revoked. Choose one to sign in again.",
                          comment: "Home sign-in-again banner body when several personal sign-ins (Apple IDs, Google accounts) expired.")
        }
        if let feedback = state.signInAgainFeedback[single.id] {
            return feedback
        }
        if let login = single.login {
            return String(localized: "The sign-in for \(login) expired or was revoked. Sign in again to keep syncing.",
                          comment: "Home sign-in-again banner body. The placeholder is the Apple ID or the Google account's e-mail.")
        }
        return String(localized: "The sign-in expired or was revoked. Sign in again to keep syncing.",
                      comment: "Home sign-in-again banner body when the Google account's e-mail is unknown.")
    }

    private func buildActionButton() -> some View {
        let isWorking = single.map { state.workingSignInIds.contains($0.id) } ?? false
        return Button {
            Task { await viewModel.startSignInAgain() }
        } label: {
            HStack(spacing: 6) {
                Text(String(localized: "Sign In Again"))
                    .font(.footnote)
                    .fontWeight(.semibold)
                if isWorking {
                    ProgressView()
                        .controlSize(.small)
                }
            }
        }
        .buttonStyle(.borderless)
        .tint(.orange)
        .disabled(isWorking)
        .accessibilityHint(single == nil
            ? String(localized: "Shows the accounts to sign in again.", comment: "Accessibility hint of the Home sign-in-again banner button with several expired sign-ins.")
            : String(localized: "Opens the sign-in for this account.", comment: "Accessibility hint of the Home sign-in-again banner button with one expired sign-in."))
    }
}

// MARK: - Sign In Again Sheet

/// What the "sign in again" banner opens: the Apple ID sign-in for one Apple
/// ID, or the list of expired sign-ins (each row signs in again; an Apple ID
/// pushes its sign-in inside the sheet).
struct HomeSignInAgainSheetView<ViewModel: HomeViewModelProtocol>: View {

    @ObservedObject var viewModel: ViewModel
    let sheet: HomeSignInAgainSheet

    var body: some View {
        NavigationStack {
            switch sheet {
            case .apple(let appleId):
                buildAppleSignIn(appleId: appleId)
                    .toolbar { buildCloseButton() }
            case .choose:
                buildList()
                    .navigationDestination(isPresented: Binding(
                        get: { viewModel.uiState.appleSignInAgainId != nil },
                        set: { if !$0 { viewModel.uiState.appleSignInAgainId = nil } }
                    )) {
                        if let appleId = viewModel.uiState.appleSignInAgainId {
                            buildAppleSignIn(appleId: appleId)
                        }
                    }
            }
        }
    }

    private func buildAppleSignIn(appleId: String) -> some View {
        AppleIdSignInViewFactory.build(mode: .signInAgain(appleId: appleId)) {
            viewModel.appleSignInAgainFinished()
        }
    }

    @ToolbarContentBuilder
    private func buildCloseButton() -> some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            StackTrackedButton(.close, on: .home) {
                viewModel.closeSignInAgainSheet()
            } label: {
                Text(String(localized: "Close"))
            }
        }
    }

    private func buildList() -> some View {
        List {
            ForEach(viewModel.uiState.expiredSignIns) { signIn in
                buildRow(signIn)
            }
        }
        .navigationTitle(String(localized: "Sign In Again"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { buildCloseButton() }
    }

    private func buildRow(_ signIn: ExpiredSignIn) -> some View {
        let isWorking = viewModel.uiState.workingSignInIds.contains(signIn.id)
        return Section {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: signIn.systemImage)
                    .foregroundStyle(.secondary)
                    .frame(width: 24)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(signIn.login ?? signIn.providerTitle)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text(signIn.accounts.map(\.name).formatted(.list(type: .and)))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if let feedback = viewModel.uiState.signInAgainFeedback[signIn.id] {
                        Text(feedback)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
            .accessibilityElement(children: .combine)

            Button {
                Task { await viewModel.signInAgain(signIn.id) }
            } label: {
                HStack {
                    Text(String(localized: "Sign In Again"))
                    Spacer()
                    if isWorking {
                        ProgressView()
                    }
                }
            }
            .disabled(isWorking)
        } header: {
            Text(signIn.providerTitle)
        }
    }
}

private extension ExpiredSignIn {
    var providerTitle: String {
        switch provider {
        case .appleId: return String(localized: "Apple ID")
        case .google: return String(localized: "Google account")
        }
    }

    var systemImage: String {
        switch provider {
        case .appleId: return "apple.logo"
        case .google: return "person.crop.circle"
        }
    }
}

// MARK: - Tip Card

/// One-time "support the project" card (rules in `TipJarPromptService`).
/// Tapping it or its button calls `onOpen` (the View opens the tip jar); either
/// that or the close button retires it for good.
struct HomeTipCard<ViewModel: HomeViewModelProtocol>: View {

    @ObservedObject var viewModel: ViewModel
    let onOpen: () -> Void

    var body: some View {
        if viewModel.uiState.showTipCard {
            StackBannerCard(
                systemImage: "heart.fill",
                tint: .pink,
                title: String(localized: "Enjoying StackConnect?"),
                message: String(localized: "It's free and open source. If it saves you time, consider leaving a tip.", comment: "Body of the Home card inviting the user to leave an optional tip."),
                onTap: { open() },
                onDismiss: { viewModel.dismissTipCard() }
            ) {
                Button {
                    open()
                } label: {
                    Text(String(localized: "tipCard.support", defaultValue: "Support", comment: "Button of the Home tip card that opens the tip jar (support the project, not customer support)."))
                        .font(.footnote)
                        .fontWeight(.semibold)
                }
                .buttonStyle(.borderless)
                .tint(.pink)
                .accessibilityHint(String(localized: "Opens the tip jar.", comment: "Accessibility hint of the Home tip card button."))
            }
        }
    }

    private func open() {
        viewModel.openTipCard()
        onOpen()
    }
}

// MARK: - Widgets Empty State

/// Shown when the dashboard has no widgets; tapping it opens Customize Widgets.
struct HomeWidgetsEmptyState: View {

    let onCustomize: () -> Void

    var body: some View {
        StackTrackedButton(.customizeWidgets, on: .home) {
            onCustomize()
        } label: {
            VStack(spacing: 10) {
                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 32))
                    .foregroundStyle(.secondary)
                Text(String(localized: "No widgets yet"))
                    .font(.headline)
                Text(String(localized: "Add widgets to keep an eye on your apps right from here."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Text(String(localized: "Add Widgets"))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.blue)
            }
            .frame(maxWidth: .infinity)
            .padding(24)
            .background(Color.gray.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Presentations

extension View {
    /// The agreements share sheet, the sign-in-again sheet and the account
    /// expiration alerts of the Home.
    func homePresentations<ViewModel: HomeViewModelProtocol>(viewModel: ViewModel) -> some View {
        modifier(HomePresentationsModifier(viewModel: viewModel))
    }
}

private struct HomePresentationsModifier<ViewModel: HomeViewModelProtocol>: ViewModifier {

    @ObservedObject var viewModel: ViewModel

    func body(content: Content) -> some View {
        content
            .stackShareSheet(item: $viewModel.uiState.agreementShare) { payload in
                payload.shareActivityItems
            }
            .sheet(item: Binding(
                get: { viewModel.uiState.signInAgainSheet },
                set: { if $0 == nil { viewModel.closeSignInAgainSheet() } }
            )) { sheet in
                HomeSignInAgainSheetView(viewModel: viewModel, sheet: sheet)
            }
            .alert(
                String(localized: "Account Expired"),
                isPresented: $viewModel.uiState.showExpiredAlert,
                presenting: viewModel.uiState.expiredAccount
            ) { account in
                StackTrackedButton(String(localized: "Re-import File"), button: .reimport, on: .home) {
                    DeepLinkRouter.shared.open(DeepLink.reimport(accountId: account.id).url)
                }
                StackTrackedButton(String(localized: "Cancel"), button: .cancel, on: .home, role: .cancel) {}
            } message: { account in
                Text("The account \"\(account.name)\" has expired. Re-import its file to keep using it, or it will stay locked.")
            }
            .alert(
                String(localized: "Account Expiring Soon"),
                isPresented: $viewModel.uiState.showExpiringSoonAlert,
                presenting: viewModel.uiState.expiringSoonAccount
            ) { account in
                StackTrackedButton(String(localized: "Re-import File"), button: .reimport, on: .home) {
                    DeepLinkRouter.shared.open(DeepLink.reimport(accountId: account.id).url)
                }
                StackTrackedButton(String(localized: "OK"), button: .ok, on: .home, role: .cancel) {}
            } message: { account in
                if let expirationDate = account.expirationDate {
                    Text("The account \"\(account.name)\" will expire on \(expirationDate.formatted(date: .abbreviated, time: .shortened)). Request a new file from the administrator before then.")
                } else {
                    Text("The account \"\(account.name)\" will expire soon. Request a new file from the administrator.")
                }
            }
    }
}
