import SwiftUI

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

    var body: some View {
        List {
            buildGroupInfoSection()
            buildTestersSection()
            buildBuildsSection()
        }
        .navigationTitle(viewModel.uiState.group.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { buildToolbar() }
        .task { await viewModel.load() }
        .refreshable { await viewModel.load() }
        .sheet(isPresented: $viewModel.uiState.showAddTester) {
            if viewModel.uiState.group.isInternalGroup {
                InternalTesterPickerSheet(
                    members: viewModel.uiState.teamMembers,
                    isLoading: viewModel.uiState.isLoadingTeamMembers,
                    isInviting: viewModel.uiState.isInvitingTesters
                ) { selected in
                    Task { await viewModel.addTeamMembersAsTesters(selected) }
                } onCancel: {
                    viewModel.uiState.showAddTester = false
                }
            } else {
                AddTesterSheet(
                    isInviting: viewModel.uiState.isInvitingTesters
                ) { email, firstName, lastName in
                    Task { await viewModel.addTester(email: email, firstName: firstName, lastName: lastName) }
                } onCancel: {
                    viewModel.uiState.showAddTester = false
                }
            }
        }
        .sheet(isPresented: $viewModel.uiState.showAddBuild) {
            AddBuildSheet(
                appId: viewModel.uiState.appId,
                account: viewModel.uiState.account,
                assignedBuildIds: Set(viewModel.uiState.builds.map(\.id)),
                builds: viewModel.uiState.allBuilds,
                isLoading: viewModel.uiState.isLoadingBuilds,
                isAdding: viewModel.uiState.isAddingBuild
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
                    locale: viewModel.uiState.submitSheetLocale,
                    isLoading: viewModel.uiState.isLoadingSubmitSheet,
                    isSubmitting: viewModel.uiState.isSubmittingForReview
                ) { text in
                    Task { await viewModel.confirmSubmitForReview(whatsNew: text) }
                } onCancel: {
                    viewModel.uiState.showSubmitSheet = false
                    viewModel.uiState.submitSheetBuild = nil
                }
            }
        }
        .alert(
            String(localized: "Error"),
            isPresented: Binding(
                get: { viewModel.uiState.inviteError != nil },
                set: { if !$0 { viewModel.uiState.inviteError = nil } }
            )
        ) {
            Button(String(localized: "OK"), role: .cancel) {
                viewModel.uiState.inviteError = nil
            }
        } message: {
            if let error = viewModel.uiState.inviteError {
                Text(error)
            }
        }
        .alert(
            String(localized: "Remove Tester"),
            isPresented: Binding(
                get: { viewModel.uiState.confirmRemoveTester != nil },
                set: { if !$0 { viewModel.uiState.confirmRemoveTester = nil } }
            )
        ) {
            Button(String(localized: "Remove"), role: .destructive) {
                if let tester = viewModel.uiState.confirmRemoveTester {
                    Task { await viewModel.removeTester(tester) }
                }
            }
            Button(String(localized: "Cancel"), role: .cancel) {}
        } message: {
            if let tester = viewModel.uiState.confirmRemoveTester {
                Text("Remove \(tester.displayName) from this group?")
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
                Text("Remove build \(build.version ?? "–") from this group?")
            }
        }
        .toast(message: $viewModel.uiState.toastMessage)
        .overlay {
            if viewModel.uiState.isRemovingTester
                || viewModel.uiState.isRemovingBuild
                || viewModel.uiState.isResendingInvite
                || viewModel.uiState.isSubmittingForReview {
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

    // MARK: - Testers

    private func buildTestersSection() -> some View {
        Section {
            if viewModel.uiState.isLoading && viewModel.uiState.testers.isEmpty {
                HStack { Spacer(); ProgressView(); Spacer() }
            } else if viewModel.uiState.testers.isEmpty {
                Text(String(localized: "No testers in this group"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.uiState.testers) { tester in
                    buildTesterRow(tester)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                viewModel.uiState.confirmRemoveTester = tester
                            } label: {
                                Label(String(localized: "Remove"), systemImage: "person.badge.minus")
                            }

                            if !viewModel.uiState.group.isInternalGroup && tester.state == "INVITED" {
                                Button {
                                    Task { await viewModel.resendInvite(tester) }
                                } label: {
                                    Label(String(localized: "Resend"), systemImage: "paperplane.fill")
                                }
                                .tint(.blue)
                            }
                        }
                }
            }

            Button {
                if viewModel.uiState.group.isInternalGroup {
                    Task { await viewModel.loadTeamMembers() }
                }
                viewModel.uiState.showAddTester = true
            } label: {
                Label(String(localized: "Add Tester"), systemImage: "plus.circle.fill")
            }
        } header: {
            HStack {
                Text("Testers")
                Spacer()
                Text("\(viewModel.uiState.testers.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func buildTesterRow(_ tester: BetaTesterModel) -> some View {
        HStack(spacing: 12) {
            Image(systemName: tester.stateIcon)
                .foregroundStyle(stateColor(tester.stateColor))
                .font(.title3)

            VStack(alignment: .leading, spacing: 2) {
                Text(tester.displayName)
                    .font(.body)

                if let email = tester.email, tester.firstName != nil {
                    Text(email)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Text(tester.stateDisplayName)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(stateColor(tester.stateColor))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(stateColor(tester.stateColor).opacity(0.12))
                .clipShape(Capsule())
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
                        buildBuildRow(build)
                            .swipeActions(edge: .trailing) {
                                if viewModel.uiState.account.canDelete(.testFlight) {
                                    Button(role: .destructive) {
                                        viewModel.uiState.confirmRemoveBuild = build
                                    } label: {
                                        Label(String(localized: "Remove"), systemImage: "trash")
                                    }
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
                }
            }

            Section {
                buildAddBuildButton()
            }
        }
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
                Text(build.version ?? "–")
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
        }
    }

    @ViewBuilder
    private func buildBadge(for build: BuildModel) -> some View {
        if build.processingState != "VALID", build.processingState != nil {
            buildStateLabel(build.processingState)
        } else if let external = build.externalBuildState, external != "NOT_APPLICABLE" {
            buildExternalStateLabel(external)
        } else {
            buildStateLabel(build.processingState)
        }
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
            viewModel.uiState.showAddBuild = true
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

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private func buildToolbar() -> some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                viewModel.uiState.showAddTester = true
            } label: {
                Image(systemName: "person.badge.plus")
            }
        }
    }

    // MARK: - Helpers

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }

    private func stateColor(_ color: AppStoreStateColor) -> Color {
        switch color {
        case .green:  return .green
        case .orange: return .orange
        case .red:    return .red
        case .gray:   return .gray
        case .blue:   return .blue
        case .yellow: return .yellow
        }
    }
}

// MARK: - Add Tester Sheet

struct AddTesterSheet: View {

    @State private var email = ""
    @State private var firstName = ""
    @State private var lastName = ""

    let isInviting: Bool
    let onAdd: (String, String?, String?) -> Void
    let onCancel: () -> Void

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
            }
            .navigationTitle(String(localized: "Add Tester"))
            .navigationBarTitleDisplayMode(.inline)
            .disabled(isInviting)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) { onCancel() }
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
        }
    }
}

// MARK: - Submit Build For Review Sheet

struct SubmitBuildForReviewSheet: View {

    let build: BuildModel
    @Binding var whatsNew: String
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
                        Text(build.version ?? "–").foregroundStyle(.secondary)
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
                    Button(String(localized: "Cancel")) { onCancel() }
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
        }
    }
}

// MARK: - Edit Beta Group Sheet

struct EditBetaGroupSheet: View {

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
                    Button(String(localized: "Cancel")) { onCancel() }
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
                    Button(String(localized: "Cancel")) { onCancel() }
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

// MARK: - Add Build Sheet

private struct AddBuildPlatformRoute: Hashable {
    let platform: String
}

struct AddBuildSheet: View {

    let appId: String
    let account: AccountModel
    let assignedBuildIds: Set<String>
    let builds: [BuildModel]
    let isLoading: Bool
    var isAdding: Bool = false
    let onAdd: (BuildModel) -> Void
    let onCancel: () -> Void

    @State private var path = NavigationPath()

    private var buildsByPlatform: [PlatformBuildGroup] {
        let sorted = builds.sorted { ($0.uploadedDate ?? .distantPast) > ($1.uploadedDate ?? .distantPast) }
        let dict = Dictionary(grouping: sorted) { $0.platform ?? "" }
        return dict
            .map { PlatformBuildGroup(platform: $0.key, builds: $0.value) }
            .sorted { BuildPlatform.sortOrder($0.platform) < BuildPlatform.sortOrder($1.platform) }
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if builds.isEmpty {
                    ContentUnavailableView {
                        Label(String(localized: "No Builds"), systemImage: "hammer")
                    } description: {
                        Text("No builds are available to add.")
                    }
                } else {
                    buildList
                }
            }
            .navigationTitle(String(localized: "Add Build"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) { onCancel() }
                }
            }
            .navigationDestination(for: AddBuildPlatformRoute.self) { route in
                AvailableBuildsForPlatformViewFactory.build(
                    appId: appId,
                    platform: route.platform,
                    account: account,
                    assignedBuildIds: assignedBuildIds,
                    isAdding: isAdding,
                    onSelect: onAdd
                )
            }
            .overlay {
                if isAdding {
                    ZStack {
                        Color.black.opacity(0.1)
                        ProgressView()
                            .scaleEffect(1.2)
                    }
                    .ignoresSafeArea()
                }
            }
        }
    }

    private var buildList: some View {
        List {
            ForEach(buildsByPlatform, id: \.platform) { group in
                Section {
                    ForEach(group.builds.prefix(5)) { build in
                        Button {
                            onAdd(build)
                        } label: {
                            buildRow(build)
                        }
                    }

                    if group.builds.count > 5 {
                        Button {
                            path.append(AddBuildPlatformRoute(platform: group.platform))
                        } label: {
                            HStack {
                                Text(String(localized: "See More"))
                                    .font(.body)
                                    .fontWeight(.medium)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .foregroundStyle(.tint)
                    }
                } header: {
                    Label(
                        BuildPlatform.label(for: group.platform),
                        systemImage: BuildPlatform.icon(for: group.platform)
                    )
                }
            }
        }
        .disabled(isAdding)
    }

    private func buildRow(_ build: BuildModel) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(build.version ?? "–")
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)

                if let date = build.uploadedDate {
                    Text(formatDate(date))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            buildStateLabel(build.processingState)
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
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
}
