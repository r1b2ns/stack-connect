import SwiftUI

// MARK: - Factory

@MainActor
struct AccountWizardViewFactory {
    /// The account wizard, to present full screen. `onClose` dismisses it
    /// (Cancel, or "View in List" once done).
    static func build(entry: AccountWizardEntry, onClose: @escaping () -> Void) -> some View {
        AccountWizardEntryView(entry: entry, onClose: onClose)
    }
}

// MARK: - Entry

private struct AccountWizardEntryView: View {
    @StateObject private var coordinator: AccountWizardCoordinator
    @StateObject private var viewModel: AccountWizardViewModel

    init(entry: AccountWizardEntry, onClose: @escaping () -> Void) {
        _coordinator = StateObject(wrappedValue: AccountWizardCoordinator(onClose: onClose))
        _viewModel = StateObject(wrappedValue: AccountWizardViewModel(entry: entry))
    }

    var body: some View {
        AccountWizardView(viewModel: viewModel)
            .environmentObject(coordinator)
    }
}

// MARK: - View

/// One wizard for every account type (plan `unified-accounts.md` §3): a
/// progress bar, the step's title and caption, the step, and one bottom
/// button. Back and Cancel sit in the navigation bar.
struct AccountWizardView<ViewModel: AccountWizardViewModelProtocol>: View {

    @ObservedObject var viewModel: ViewModel
    @EnvironmentObject private var coordinator: AccountWizardCoordinator

    private var state: AccountWizardUiState { viewModel.uiState }

    var body: some View {
        NavigationStack {
            Group {
                if let result = state.result {
                    AccountWizardDoneView(
                        result: result,
                        onViewInList: { coordinator.close() },
                        onAddAnother: { viewModel.addAnotherAccount() }
                    )
                } else {
                    buildStep()
                }
            }
            .navigationTitle(AccountWizardCopy.headerTitle(for: state))
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden()
            .toolbar { buildToolbar() }
        }
        // Half-typed credentials must not go away with a stray swipe.
        .interactiveDismissDisabled()
        .sheet(item: Binding(
            get: { viewModel.uiState.guide },
            set: { if $0 == nil { viewModel.dismissConnectionGuide() } }
        )) { guide in
            buildGuide(guide)
        }
        .sheet(isPresented: $coordinator.isShowingImportTutorial) {
            ImportTutorialView()
        }
        .onDisappear {
            Task { await viewModel.discard() }
        }
    }

    // MARK: - Step

    private func buildStep() -> some View {
        Form {
            buildHeaderSection()
            buildContent()
            if let error = state.errorMessage {
                AccountWizardErrorSection(message: error)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            AccountWizardProgressHeader(progress: state.progress, label: AccountWizardCopy.stepLabel(for: state), tint: tint)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            buildPrimaryButton()
        }
        .disabled(state.isWorking)
        .appleSignInLifecycle(state.method == .appleIdSignIn ? viewModel.appleSignIn : nil)
        .fileImporter(
            isPresented: $coordinator.isShowingFileImporter,
            allowedContentTypes: [.data],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first { viewModel.selectImportFile(url) }
            case .failure(let error):
                Log.print.error("[AccountWizard] File picker error: \(error.localizedDescription)")
            }
        }
        // A new step is a new screen. The appear-driven modifiers must sit
        // *inside* `.id(state.step)`: the id recreates this subtree on every
        // step change, so their `onAppear` runs once per step shown (going
        // back counts again). Applied outside the id, they would belong to a
        // view whose identity never changes and fire for the first step only.
        .trackScreen(state.step.analyticsScreen)
        .onAppear {
            if state.step == .credentials { viewModel.credentialsStepDidAppear() }
        }
        .id(state.step)
        .animation(.default, value: state.step)
    }

    private func buildHeaderSection() -> some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text(AccountWizardCopy.title(for: state))
                    .font(.title2)
                    .fontWeight(.bold)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                if let caption = AccountWizardCopy.caption(for: state) {
                    Text(caption)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .listRowInsets(EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4))
            .listRowBackground(Color.clear)
        }
    }

    @ViewBuilder
    private func buildContent() -> some View {
        switch state.step {
        case .type:
            AccountWizardTypeStepView(config: state.config) { viewModel.chooseKind($0) }
        case .method:
            if let kind = state.kind {
                AccountWizardMethodStepView(kind: kind, selected: state.method) { viewModel.chooseMethod($0) }
            }
        case .credentials:
            buildCredentials()
        case .code:
            if let apple = viewModel.appleSignIn {
                AppleIdSignInSections(viewModel: apple, showsActionButtons: false)
            }
        case .items:
            buildItems()
        case .review:
            buildReview()
        }
    }

    // MARK: Credentials (one component per auth style)

    @ViewBuilder
    private func buildCredentials() -> some View {
        if showsHowItWorks {
            AccountWizardHowItWorksSection { viewModel.showConnectionGuide() }
        }

        switch state.method {
        case .apiKey?, .serviceAccount?:
            if let connection = viewModel.connection {
                AccountWizardKeyFileCredentialsView(viewModel: connection)
            }
        case .googleSignIn?:
            if let account = state.reconnectAccount {
                AccountWizardGoogleReconnectView(account: account)
            } else if let connection = viewModel.connection {
                AccountWizardGoogleSignInView(viewModel: connection)
            }
        case .appleIdSignIn?:
            if let apple = viewModel.appleSignIn {
                AppleIdSignInSections(viewModel: apple, showsActionButtons: false)
            }
        case .scexportFile?:
            AccountWizardImportCredentialsView(
                importFile: $viewModel.uiState.importFile,
                onPickFile: { coordinator.presentFileImporter() },
                onShowTutorial: { coordinator.presentImportTutorial() }
            )
        case nil:
            EmptyView()
        }
    }

    /// The credentials explainer of PR #109 (flag `accountConnectionGuide`):
    /// for the store kinds, not when reconnecting.
    private var showsHowItWorks: Bool {
        state.isConnectionGuideEnabled && !state.entry.isReconnect
            && state.kind?.kind.provider != nil
    }

    // MARK: Items

    @ViewBuilder
    private func buildItems() -> some View {
        switch state.method {
        case .appleIdSignIn?:
            if let apple = viewModel.appleSignIn {
                AppleIdSignInSections(viewModel: apple, showsActionButtons: false)
            }
        case .googleSignIn?:
            if let connection = viewModel.connection {
                AccountWizardGooglePickerView(viewModel: connection)
            }
        default:
            EmptyView()
        }
    }

    // MARK: Review

    @ViewBuilder
    private func buildReview() -> some View {
        if let kind = state.kind, let method = state.method {
            switch method {
            case .apiKey, .serviceAccount, .googleSignIn:
                if let connection = viewModel.connection {
                    AccountWizardConnectionReview(viewModel: connection, kind: kind, method: method)
                }
            case .appleIdSignIn:
                if let apple = viewModel.appleSignIn {
                    AccountWizardAppleReview(viewModel: apple, kind: kind)
                }
            case .scexportFile:
                AccountWizardImportReview(importFile: $viewModel.uiState.importFile)
            }
        }
    }

    // MARK: Bottom button

    @ViewBuilder
    private func buildPrimaryButton() -> some View {
        if let title = viewModel.primaryTitle {
            VStack(spacing: 0) {
                Divider()
                Button {
                    Task { await viewModel.primaryAction() }
                } label: {
                    HStack(spacing: 8) {
                        if isBusy {
                            ProgressView()
                                .tint(.white)
                        }
                        Text(title)
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(tint)
                .disabled(!viewModel.canContinue)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(.bar)
        }
    }

    /// The wizard or the engine of the step is waiting on the network.
    private var isBusy: Bool {
        state.isWorking
            || viewModel.connection?.uiState.isBusy == true
            || viewModel.appleSignIn?.uiState.isWorking == true
    }

    private var tint: Color {
        state.tintProvider?.color ?? .accentColor
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private func buildToolbar() -> some ToolbarContent {
        if viewModel.canGoBack {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    viewModel.goBack()
                } label: {
                    Label(String(localized: "Back"), systemImage: "chevron.backward")
                        .labelStyle(.titleAndIcon)
                }
            }
        }
        if !state.isFinished {
            // Trailing, not `.cancellationAction`: on iOS 26 that placement sits
            // on the leading side and shares Back's glass capsule.
            ToolbarItem(placement: .topBarTrailing) {
                StackTrackedButton(String(localized: "Cancel"), button: .cancel, on: state.step.analyticsScreen) {
                    coordinator.close()
                }
            }
        }
    }

    // MARK: Connection guide

    @ViewBuilder
    private func buildGuide(_ guide: AccountWizardGuide) -> some View {
        if let provider = state.provider {
            let methods = state.kind?.methods.compactMap(\.connectionMethod) ?? []
            switch guide {
            case .firstConnection:
                // Before the first connection: Skip / Continue go on to the
                // credentials; Cancel leaves the wizard, as it left Add Account.
                NavigationStack {
                    ConnectionGuideViewFactory.buildFirstConnection(
                        provider: provider,
                        methods: methods,
                        onContinue: { viewModel.dismissConnectionGuide() },
                        onCancel: {
                            viewModel.dismissConnectionGuide()
                            coordinator.close()
                        }
                    )
                }
                .interactiveDismissDisabled()
            case .reopened:
                ConnectionGuideViewFactory.buildReopened(provider: provider, methods: methods) {
                    viewModel.dismissConnectionGuide()
                }
            }
        }
    }
}

// MARK: - Progress header

/// The progress bar and "Step 2 of 4 · Credentials".
struct AccountWizardProgressHeader: View {
    let progress: Double
    let label: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ProgressView(value: progress)
                .tint(tint)
                .accessibilityHidden(true)
            Text(label)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemGroupedBackground))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Error row

/// A failure inside a `Form`, as its own section.
struct AccountWizardErrorSection: View {
    let message: String

    var body: some View {
        Section {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Apple sign-in lifecycle

private extension View {
    @ViewBuilder
    func appleSignInLifecycle<AppleSignIn: AppleIdSignInViewModelProtocol>(_ viewModel: AppleSignIn?) -> some View {
        if let viewModel {
            modifier(AccountWizardAppleSignInLifecycle(viewModel: viewModel))
        } else {
            self
        }
    }
}
