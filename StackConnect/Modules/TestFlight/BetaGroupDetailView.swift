import SwiftUI
import UniformTypeIdentifiers

// MARK: - Factory

@MainActor
struct BetaGroupDetailViewFactory {
    static func build(group: BetaGroupModel, appId: String, account: AccountModel) -> some View {
        BetaGroupDetailEntryView(group: group, appId: appId, account: account)
    }
}

// MARK: - Entry

private struct BetaGroupDetailEntryView: View {
    let group: BetaGroupModel
    let appId: String
    let account: AccountModel

    @StateObject private var viewModel: BetaGroupDetailViewModel

    init(group: BetaGroupModel, appId: String, account: AccountModel) {
        self.group = group
        self.appId = appId
        self.account = account
        _viewModel = StateObject(wrappedValue: BetaGroupDetailViewModel(group: group, appId: appId, account: account))
    }

    var body: some View {
        BetaGroupDetailView(viewModel: viewModel)
    }
}

// MARK: - View

struct BetaGroupDetailView<ViewModel: BetaGroupDetailViewModelProtocol>: View {

    @ObservedObject var viewModel: ViewModel
    @EnvironmentObject private var homeCoordinator: HomeCoordinator

    var body: some View {
        List {
            buildGroupInfoSection()
            buildTestInformationSection()
            buildTestersNavigationSection()
            buildBuildsSection()
        }
        .navigationTitle(viewModel.uiState.group.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
        .onAppear { Task { await viewModel.loadTestInformation() } }
        .refreshable { await viewModel.load() }
        .sheet(isPresented: $viewModel.uiState.showAddBuild) {
            BuildPickerSheet(
                title: String(localized: "Add Build"),
                appId: viewModel.uiState.appId,
                account: viewModel.uiState.account,
                assignedBuildIds: Set(viewModel.uiState.builds.map(\.id)),
                builds: viewModel.uiState.allBuilds,
                isLoading: viewModel.uiState.isLoadingBuilds,
                isBusy: viewModel.uiState.isAddingBuild
            ) { build in
                Task { await viewModel.addBuildToGroup(buildId: build.id) }
            } onCancel: {
                viewModel.uiState.showAddBuild = false
            }
            .task { await viewModel.loadAvailableBuilds() }
        }
        .sheet(isPresented: $viewModel.uiState.showEditGroup) {
            EditBetaGroupSheet(group: viewModel.uiState.group) { name, publicLink, limit, feedback in
                Task { await viewModel.updateGroup(name: name, isPublicLinkEnabled: publicLink, publicLinkLimit: limit, isFeedbackEnabled: feedback) }
            } onCancel: {
                viewModel.uiState.showEditGroup = false
            }
        }
        .sheet(isPresented: $viewModel.uiState.showSubmitSheet) {
            if let build = viewModel.uiState.submitSheetBuild {
                SubmitBuildForReviewSheet(
                    build: build,
                    whatsNew: $viewModel.uiState.submitSheetWhatsNew,
                    errorMessage: $viewModel.uiState.submitError,
                    locale: viewModel.uiState.submitSheetLocale,
                    isLoading: viewModel.uiState.isLoadingSubmitSheet,
                    isSubmitting: viewModel.uiState.isSubmittingForReview
                ) { text in
                    Task { await viewModel.confirmSubmitForReview(whatsNew: text) }
                } onCancel: {
                    viewModel.uiState.showSubmitSheet = false
                    viewModel.uiState.submitSheetBuild = nil
                    viewModel.uiState.submitError = nil
                }
            }
        }
        .alert(
            String(localized: "Remove Build"),
            isPresented: Binding(
                get: { viewModel.uiState.confirmRemoveBuild != nil },
                set: { if !$0 { viewModel.uiState.confirmRemoveBuild = nil } }
            )
        ) {
            Button(String(localized: "Remove"), role: .destructive) {
                if let build = viewModel.uiState.confirmRemoveBuild {
                    Task { await viewModel.removeBuildFromGroup(build) }
                }
            }
            Button(String(localized: "Cancel"), role: .cancel) {}
        } message: {
            if let build = viewModel.uiState.confirmRemoveBuild {
                Text("Remove build \(build.displayVersion) from this group?")
            }
        }
        .alert(
            String(localized: "Expire Build"),
            isPresented: Binding(
                get: { viewModel.uiState.confirmExpireBuild != nil },
                set: { if !$0 { viewModel.uiState.confirmExpireBuild = nil } }
            )
        ) {
            Button(String(localized: "Expire"), role: .destructive) {
                if let build = viewModel.uiState.confirmExpireBuild {
                    Task { await viewModel.expireBuild(build) }
                }
            }
            Button(String(localized: "Cancel"), role: .cancel) {}
        } message: {
            if let build = viewModel.uiState.confirmExpireBuild {
                Text("Expire build \(build.displayVersion)? Testers will no longer be able to install it. This cannot be undone via the API.")
            }
        }
        .alert(
            String(localized: "Expire Failed"),
            isPresented: Binding(
                get: { viewModel.uiState.expireError != nil },
                set: { if !$0 { viewModel.uiState.expireError = nil } }
            )
        ) {
            Button(String(localized: "OK"), role: .cancel) {}
        } message: {
            if let message = viewModel.uiState.expireError {
                Text(message)
            }
        }
        .alert(
            String(localized: "Test Information Required"),
            isPresented: $viewModel.uiState.showTestInformationRequiredAlert
        ) {
            Button(String(localized: "Edit Test Information")) {
                homeCoordinator.navigateToBetaAppReviewInfo(
                    appId: viewModel.uiState.appId,
                    account: viewModel.uiState.account
                )
            }
            Button(String(localized: "Cancel"), role: .cancel) {}
        } message: {
            Text("You must complete the Test Information before adding a build to a public group.")
        }
        .toast(message: $viewModel.uiState.toastMessage)
        .overlay {
            if viewModel.uiState.isRemovingBuild
                || viewModel.uiState.isSubmittingForReview
                || viewModel.uiState.isExpiringBuild {
                ZStack {
                    Color.black.opacity(0.1)
                    ProgressView()
                        .scaleEffect(1.2)
                }
                .ignoresSafeArea()
            }
        }
    }

    // MARK: - Group Info

    private func buildGroupInfoSection() -> some View {
        Section {
            HStack {
                Label(String(localized: "Type"), systemImage: viewModel.uiState.group.isInternalGroup ? "lock.fill" : "globe")
                Spacer()
                Text(viewModel.uiState.group.isInternalGroup ? String(localized: "Internal") : String(localized: "External"))
                    .foregroundStyle(.secondary)
            }

            if !viewModel.uiState.group.isInternalGroup {
                HStack {
                    Label(String(localized: "Public Link"), systemImage: "link")
                    Spacer()
                    Text(viewModel.uiState.group.isPublicLinkEnabled ? String(localized: "Enabled") : String(localized: "Disabled"))
                        .foregroundStyle(viewModel.uiState.group.isPublicLinkEnabled ? .green : .secondary)
                }

                if viewModel.uiState.group.isPublicLinkEnabled, let link = viewModel.uiState.group.publicLink {
                    ShareLink(item: link) {
                        HStack {
                            Text(link)
                                .font(.caption)
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Spacer()
                            Image(systemName: "square.and.arrow.up")
                                .font(.caption)
                                .foregroundStyle(.blue)
                        }
                    }
                }
            }

            HStack {
                Label(String(localized: "Feedback"), systemImage: "bubble.left.fill")
                Spacer()
                Text(viewModel.uiState.group.isFeedbackEnabled ? String(localized: "Enabled") : String(localized: "Disabled"))
                    .foregroundStyle(.secondary)
            }

            if let date = viewModel.uiState.group.createdDate {
                HStack {
                    Label(String(localized: "Created"), systemImage: "calendar")
                    Spacer()
                    Text(formatDate(date))
                        .foregroundStyle(.secondary)
                }
            }

            Button {
                viewModel.uiState.showEditGroup = true
            } label: {
                Label(String(localized: "Edit Group Settings"), systemImage: "pencil")
            }
        } header: {
            Text("Group Info")
        }
    }

    // MARK: - Test Information

    @ViewBuilder
    private func buildTestInformationSection() -> some View {
        if !viewModel.uiState.group.isInternalGroup {
            Section {
                Button {
                    homeCoordinator.navigateToBetaAppReviewInfo(
                        appId: viewModel.uiState.appId,
                        account: viewModel.uiState.account
                    )
                } label: {
                    HStack {
                        Label(String(localized: "Test Information"), systemImage: "doc.text")
                            .foregroundStyle(.primary)
                        Spacer()
                        if !viewModel.uiState.isTestInformationComplete {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                        }
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }

    // MARK: - Testers

    private func buildTestersNavigationSection() -> some View {
        Section {
            Button {
                homeCoordinator.navigateToBetaGroupTesters(
                    group: viewModel.uiState.group,
                    appId: viewModel.uiState.appId,
                    account: viewModel.uiState.account
                )
            } label: {
                HStack {
                    Label(String(localized: "Testers"), systemImage: "person.2.fill")
                        .foregroundStyle(.primary)
                    Spacer()
                    if let count = viewModel.uiState.group.testerCount {
                        Text("\(count)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    // MARK: - Builds

    @ViewBuilder
    private func buildBuildsSection() -> some View {
        if viewModel.uiState.isLoading && viewModel.uiState.builds.isEmpty {
            Section {
                HStack { Spacer(); ProgressView(); Spacer() }
            } header: {
                buildsHeader
            }
        } else if viewModel.uiState.builds.isEmpty {
            Section {
                Text(String(localized: "No builds assigned to this group"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                buildAddBuildButton()
            } header: {
                buildsHeader
            }
        } else {
            ForEach(viewModel.uiState.buildsByPlatform, id: \.platform) { group in
                Section {
                    ForEach(group.builds) { build in
                        Button {
                            homeCoordinator.navigateToBuildDetail(
                                build: build,
                                appId: viewModel.uiState.appId,
                                account: viewModel.uiState.account
                            )
                        } label: {
                            buildBuildRow(build)
                        }
                        .foregroundStyle(.primary)
                        .swipeActions(edge: .trailing) {
                            if viewModel.uiState.account.canDelete(.testFlight) {
                                Button(role: .destructive) {
                                    viewModel.uiState.confirmRemoveBuild = build
                                } label: {
                                    Label(String(localized: "Remove"), systemImage: "trash")
                                }
                            }

                            if !build.isExpired && viewModel.uiState.account.canDelete(.testFlight) {
                                Button {
                                    viewModel.uiState.confirmExpireBuild = build
                                } label: {
                                    Label(String(localized: "Expire"), systemImage: "clock.badge.xmark")
                                }
                                .tint(.orange)
                            }

                            if !viewModel.uiState.group.isInternalGroup
                                && build.canSubmitForBetaReview
                                && viewModel.uiState.account.canEdit(.testFlight) {
                                Button {
                                    Task { await viewModel.startSubmitForReview(build) }
                                } label: {
                                    Label(String(localized: "Submit"), systemImage: "paperplane.fill")
                                }
                                .tint(.blue)
                            }
                        }
                    }
                } header: {
                    HStack {
                        Label(
                            BuildPlatform.label(for: group.platform),
                            systemImage: BuildPlatform.icon(for: group.platform)
                        )
                        Spacer()
                        Text("\(group.builds.count)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } footer: {
                    if shouldShowSubmitFooter(for: group) {
                        Text("Swipe left on a build to submit it for beta review.")
                    }
                }
            }

            Section {
                buildAddBuildButton()
            }
        }
    }

    private func shouldShowSubmitFooter(for group: PlatformBuildGroup) -> Bool {
        guard !viewModel.uiState.group.isInternalGroup,
              viewModel.uiState.account.canEdit(.testFlight)
        else { return false }
        return group.builds.contains(where: { $0.canSubmitForBetaReview })
    }

    private var buildsHeader: some View {
        HStack {
            Text("Builds")
            Spacer()
            Text("\(viewModel.uiState.builds.count)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func buildBuildRow(_ build: BuildModel) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(build.displayVersion)
                    .font(.body)
                    .fontWeight(.medium)

                if let date = build.uploadedDate {
                    Text(formatDate(date))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            buildBadge(for: build)

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private func buildBadge(for build: BuildModel) -> some View {
        if build.isExpired {
            buildExpiredLabel()
        } else if build.processingState != "VALID", build.processingState != nil {
            buildStateLabel(build.processingState)
        } else if let external = build.externalBuildState, external != "NOT_APPLICABLE" {
            buildExternalStateLabel(external)
        } else {
            buildStateLabel(build.processingState)
        }
    }

    private func buildExpiredLabel() -> some View {
        Text(String(localized: "Expired"))
            .font(.caption)
            .fontWeight(.medium)
            .foregroundStyle(.gray)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.gray.opacity(0.12))
            .clipShape(Capsule())
    }

    private func buildExternalStateLabel(_ state: String) -> some View {
        let (text, color): (String, Color) = {
            switch state {
            case "READY_FOR_BETA_SUBMISSION":   return (String(localized: "Ready to Submit"), .orange)
            case "WAITING_FOR_BETA_REVIEW":     return (String(localized: "Waiting Review"), .orange)
            case "IN_BETA_REVIEW":              return (String(localized: "In Review"), .blue)
            case "BETA_REJECTED":               return (String(localized: "Rejected"), .red)
            case "BETA_APPROVED":               return (String(localized: "Approved"), .green)
            case "READY_FOR_BETA_TESTING":     return (String(localized: "Ready for Testing"), .green)
            case "IN_BETA_TESTING":             return (String(localized: "Testing"), .green)
            case "MISSING_EXPORT_COMPLIANCE":   return (String(localized: "Export Compliance"), .red)
            case "IN_EXPORT_COMPLIANCE_REVIEW": return (String(localized: "Compliance Review"), .blue)
            case "EXPIRED":                     return (String(localized: "Expired"), .gray)
            case "PROCESSING":                  return (String(localized: "Processing"), .orange)
            case "PROCESSING_EXCEPTION":        return (String(localized: "Failed"), .red)
            default:                            return (state, .gray)
            }
        }()

        return Text(text)
            .font(.caption)
            .fontWeight(.medium)
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }

    private func buildAddBuildButton() -> some View {
        Button {
            viewModel.requestAddBuild()
        } label: {
            Label(String(localized: "Add Build"), systemImage: "plus.circle.fill")
        }
    }

    private func buildStateLabel(_ state: String?) -> some View {
        let (text, color): (String, Color) = {
            switch state {
            case "VALID":      return (String(localized: "Ready"), .green)
            case "PROCESSING": return (String(localized: "Processing"), .orange)
            case "FAILED":     return (String(localized: "Failed"), .red)
            case "INVALID":    return (String(localized: "Invalid"), .red)
            default:           return ("–", .gray)
            }
        }()

        return Text(text)
            .font(.caption)
            .fontWeight(.medium)
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }

    // MARK: - Helpers

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
}

// MARK: - Add Tester Sheet

struct AddTesterSheet: View {

    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var isPresentingFilePicker = false
    @State private var csvRows: [CSVTesterRow] = []
    @State private var showCSVPreview = false
    @State private var csvError: String?

    let existingTesters: [BetaTesterModel]
    let isInviting: Bool
    let onAdd: (String, String?, String?) -> Void
    let onImportCSV: ([CSVTesterRow]) -> Void
    let onCancel: () -> Void

    private var existingEmails: Set<String> {
        Set(existingTesters.compactMap { $0.email?.lowercased() })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(String(localized: "Email"), text: $email)
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                } header: {
                    Text("Email (required)")
                }

                Section {
                    TextField(String(localized: "First Name"), text: $firstName)
                        .textContentType(.givenName)
                    TextField(String(localized: "Last Name"), text: $lastName)
                        .textContentType(.familyName)
                } header: {
                    Text("Name (optional)")
                }

                Section {
                    Button {
                        isPresentingFilePicker = true
                    } label: {
                        Label(String(localized: "Import CSV"), systemImage: "square.and.arrow.down")
                    }
                } footer: {
                    Text("CSV columns expected in order: name, lastName, email.")
                }
            }
            .navigationTitle(String(localized: "Add Tester"))
            .navigationBarTitleDisplayMode(.inline)
            .disabled(isInviting)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) {
                        dismiss()
                        onCancel()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isInviting {
                        ProgressView()
                    } else {
                        Button(String(localized: "Invite")) {
                            onAdd(
                                email.trimmingCharacters(in: .whitespaces),
                                firstName.isEmpty ? nil : firstName,
                                lastName.isEmpty ? nil : lastName
                            )
                        }
                        .disabled(email.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            .fileImporter(
                isPresented: $isPresentingFilePicker,
                allowedContentTypes: [.commaSeparatedText],
                allowsMultipleSelection: false
            ) { result in
                handleCSVPick(result)
            }
            .navigationDestination(isPresented: $showCSVPreview) {
                CSVTesterImportView(
                    rows: csvRows,
                    existingEmails: existingEmails,
                    isInviting: isInviting,
                    onContinue: { toImport in
                        onImportCSV(toImport)
                    },
                    onCancel: {
                        showCSVPreview = false
                    }
                )
            }
            .alert(
                String(localized: "Import Failed"),
                isPresented: Binding(
                    get: { csvError != nil },
                    set: { if !$0 { csvError = nil } }
                )
            ) {
                Button(String(localized: "OK"), role: .cancel) { csvError = nil }
            } message: {
                if let message = csvError { Text(message) }
            }
        }
    }

    private func handleCSVPick(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            do {
                let data = try Data(contentsOf: url)
                let text = String(data: data, encoding: .utf8)
                    ?? String(data: data, encoding: .isoLatin1)
                    ?? ""
                csvRows = CSVTesterParser.parse(text)
                showCSVPreview = true
            } catch {
                csvError = error.localizedDescription
                Log.print.error("[AddTesterSheet] Failed to read CSV: \(error.localizedDescription)")
            }
        case .failure(let error):
            csvError = error.localizedDescription
            Log.print.error("[AddTesterSheet] File picker failed: \(error.localizedDescription)")
        }
    }
}

// MARK: - Submit Build For Review Sheet

struct SubmitBuildForReviewSheet: View {

    @Environment(\.dismiss) private var dismiss
    let build: BuildModel
    @Binding var whatsNew: String
    @Binding var errorMessage: String?
    let locale: String
    let isLoading: Bool
    let isSubmitting: Bool
    let onSubmit: (String) -> Void
    let onCancel: () -> Void

    private var trimmedWhatsNew: String {
        whatsNew.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text("Build")
                        Spacer()
                        Text(build.displayVersion).foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Locale")
                        Spacer()
                        Text(locale).foregroundStyle(.secondary)
                    }
                }

                Section {
                    TextEditor(text: $whatsNew)
                        .frame(minHeight: 140)
                } header: {
                    Text("What to Test (required)")
                } footer: {
                    Text("Apple requires testers to know what to test. This text is saved to the build and sent with the review submission.")
                }
            }
            .navigationTitle(String(localized: "Submit for Review"))
            .navigationBarTitleDisplayMode(.inline)
            .disabled(isLoading || isSubmitting)
            .overlay {
                if isLoading {
                    ZStack {
                        Color.black.opacity(0.05).ignoresSafeArea()
                        ProgressView()
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) {
                        dismiss()
                        onCancel()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSubmitting {
                        ProgressView()
                    } else {
                        Button(String(localized: "Submit")) {
                            onSubmit(trimmedWhatsNew)
                        }
                        .disabled(trimmedWhatsNew.isEmpty)
                    }
                }
            }
            .alert(
                String(localized: "Submit Failed"),
                isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { if !$0 { errorMessage = nil } }
                )
            ) {
                Button(String(localized: "OK"), role: .cancel) {}
            } message: {
                if let message = errorMessage {
                    Text(message)
                }
            }
        }
    }
}

// MARK: - Edit Beta Group Sheet

struct EditBetaGroupSheet: View {

    @Environment(\.dismiss) private var dismiss
    @State var name: String
    @State var isPublicLinkEnabled: Bool
    @State var publicLinkLimit: String
    @State var isFeedbackEnabled: Bool
    let isInternal: Bool

    let onSave: (String?, Bool?, Int?, Bool?) -> Void
    let onCancel: () -> Void

    init(group: BetaGroupModel, onSave: @escaping (String?, Bool?, Int?, Bool?) -> Void, onCancel: @escaping () -> Void) {
        _name = State(initialValue: group.name)
        _isPublicLinkEnabled = State(initialValue: group.isPublicLinkEnabled)
        _publicLinkLimit = State(initialValue: group.publicLinkLimit.map { String($0) } ?? "")
        _isFeedbackEnabled = State(initialValue: group.isFeedbackEnabled)
        self.isInternal = group.isInternalGroup
        self.onSave = onSave
        self.onCancel = onCancel
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(String(localized: "Group Name"), text: $name)
                } header: {
                    Text("Name")
                }

                Section {
                    Toggle(String(localized: "Feedback Enabled"), isOn: $isFeedbackEnabled)
                }

                if !isInternal {
                    Section {
                        Toggle(String(localized: "Public Link"), isOn: $isPublicLinkEnabled)

                        if isPublicLinkEnabled {
                            TextField(String(localized: "Tester Limit"), text: $publicLinkLimit)
                                .keyboardType(.numberPad)
                        }
                    } header: {
                        Text("Public Link")
                    } footer: {
                        Text("Enable to allow anyone with the link to join testing.")
                    }
                }
            }
            .navigationTitle(String(localized: "Edit Group"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) {
                        dismiss()
                        onCancel()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Save")) {
                        onSave(
                            name.trimmingCharacters(in: .whitespaces),
                            isInternal ? nil : isPublicLinkEnabled,
                            Int(publicLinkLimit),
                            isFeedbackEnabled
                        )
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

// MARK: - Internal Tester Picker Sheet

struct InternalTesterPickerSheet: View {

    let members: [TeamMemberModel]
    let isLoading: Bool
    var isInviting: Bool = false
    let onInvite: ([TeamMemberModel]) -> Void
    let onCancel: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selected: Set<String> = []

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if members.isEmpty {
                    ContentUnavailableView {
                        Label(String(localized: "No Team Members"), systemImage: "person.slash")
                    } description: {
                        Text("No App Store Connect team members found.")
                    }
                } else {
                    List(members) { member in
                        Button {
                            if selected.contains(member.id) {
                                selected.remove(member.id)
                            } else {
                                selected.insert(member.id)
                            }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: selected.contains(member.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selected.contains(member.id) ? .blue : .secondary)
                                    .font(.title3)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(member.displayName)
                                        .font(.body)
                                        .foregroundStyle(.primary)

                                    if let email = member.username {
                                        Text(email)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }

                                    if !member.roles.isEmpty {
                                        Text(member.rolesDisplayName)
                                            .font(.caption2)
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(String(localized: "Select Testers"))
            .navigationBarTitleDisplayMode(.inline)
            .disabled(isInviting)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) {
                        dismiss()
                        onCancel()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isInviting {
                        ProgressView()
                    } else {
                        Button(String(localized: "Invite")) {
                            let selectedMembers = members.filter { selected.contains($0.id) }
                            onInvite(selectedMembers)
                        }
                        .disabled(selected.isEmpty)
                    }
                }
            }
        }
    }
}
