import SwiftUI

// MARK: - Factory

@MainActor
struct BuildDetailViewFactory {
    static func build(build: BuildModel, appId: String, account: AccountModel) -> some View {
        BuildDetailEntry(build: build, appId: appId, account: account)
    }
}

// MARK: - Entry

private struct BuildDetailEntry: View {
    let build: BuildModel
    let appId: String
    let account: AccountModel

    @StateObject private var viewModel: BuildDetailViewModel

    init(build: BuildModel, appId: String, account: AccountModel) {
        self.build = build
        self.appId = appId
        self.account = account
        _viewModel = StateObject(wrappedValue: BuildDetailViewModel(build: build, appId: appId, account: account))
    }

    var body: some View {
        BuildDetailView(viewModel: viewModel)
    }
}

// MARK: - View

struct BuildDetailView<ViewModel: BuildDetailViewModelProtocol>: View {

    @ObservedObject var viewModel: ViewModel

    var body: some View {
        List {
            buildVersionSection()
            buildPlatformSection()
            buildBetaReviewSection()
            buildOptionsSection()
            buildBetaGroupsSection()
            buildWhatToTestSection()
            buildActionsSection()
        }
        .navigationTitle(viewModel.uiState.build.displayVersion)
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
        .refreshable { await viewModel.load() }
        .toast(message: $viewModel.uiState.toastMessage)
        .alert(
            String(localized: "Expire Build"),
            isPresented: $viewModel.uiState.showExpireConfirm
        ) {
            Button(String(localized: "Cancel"), role: .cancel) {}
            Button(String(localized: "Expire"), role: .destructive) {
                Task { await viewModel.expireBuild() }
            }
        } message: {
            Text("Expired builds cannot be installed by testers. This action cannot be undone via the API — only Apple support can restore an expired build.")
        }
        .overlay {
            if viewModel.uiState.isExpiring {
                ZStack {
                    Color.black.opacity(0.1)
                    ProgressView()
                        .scaleEffect(1.2)
                }
                .ignoresSafeArea()
            }
        }
    }

    // MARK: - Version Section

    private func buildVersionSection() -> some View {
        Section {
            buildInfoRow(label: String(localized: "Marketing Version"), value: viewModel.uiState.build.marketingVersion ?? "–")
            buildInfoRow(label: String(localized: "Build Number"), value: viewModel.uiState.build.version ?? "–")

            if let date = viewModel.uiState.build.uploadedDate {
                buildInfoRow(label: String(localized: "Uploaded"), value: formatDateTime(date))
            }
            if let date = viewModel.uiState.build.expirationDate {
                buildInfoRow(label: String(localized: "Expires"), value: formatDateTime(date))
            }
            if viewModel.uiState.build.isExpired {
                HStack {
                    Label(String(localized: "Expired"), systemImage: "clock.badge.xmark.fill")
                        .foregroundStyle(.red)
                    Spacer()
                }
            }
        } header: {
            Text("Version")
        }
    }

    // MARK: - Platform Section

    private func buildPlatformSection() -> some View {
        Section {
            if let platform = viewModel.uiState.build.platform {
                HStack {
                    Label(BuildPlatform.label(for: platform), systemImage: BuildPlatform.icon(for: platform))
                    Spacer()
                }
            }
            if let min = viewModel.uiState.build.minOsVersion {
                buildInfoRow(label: String(localized: "Min OS Version"), value: min)
            }
            if let mac = viewModel.uiState.build.computedMinMacOsVersion {
                buildInfoRow(label: String(localized: "Min macOS"), value: mac)
            }
            if let vision = viewModel.uiState.build.computedMinVisionOsVersion {
                buildInfoRow(label: String(localized: "Min visionOS"), value: vision)
            }
        } header: {
            Text("Platform & Compatibility")
        }
    }

    // MARK: - Beta Review Section

    @ViewBuilder
    private func buildBetaReviewSection() -> some View {
        let build = viewModel.uiState.build
        if build.processingState != nil || build.externalBuildState != nil || build.internalBuildState != nil {
            Section {
                if let state = build.processingState {
                    buildInfoRow(label: String(localized: "Processing"), value: processingLabel(state))
                }
                if let state = build.externalBuildState, state != "NOT_APPLICABLE" {
                    buildInfoRow(label: String(localized: "External State"), value: externalStateLabel(state))
                }
                if let state = build.internalBuildState {
                    buildInfoRow(label: String(localized: "Internal State"), value: externalStateLabel(state))
                }
                if let state = build.betaReviewState {
                    buildInfoRow(label: String(localized: "Beta Review"), value: betaReviewLabel(state))
                }
                if let date = build.submittedDate {
                    buildInfoRow(label: String(localized: "Submitted"), value: formatDateTime(date))
                }
            } header: {
                Text("Beta Review")
            }
        }
    }

    // MARK: - Options Section

    @ViewBuilder
    private func buildOptionsSection() -> some View {
        let build = viewModel.uiState.build
        let hasContent = build.buildAudienceType != nil || build.usesNonExemptEncryption != nil || build.autoNotifyEnabled != nil
        if hasContent {
            Section {
                if let audience = build.buildAudienceType {
                    buildInfoRow(label: String(localized: "Audience"), value: audienceLabel(audience))
                }
                if let auto = build.autoNotifyEnabled {
                    HStack {
                        Text("Auto-Notify Testers")
                        Spacer()
                        Image(systemName: auto ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(auto ? .green : .secondary)
                    }
                }
                if let enc = build.usesNonExemptEncryption {
                    HStack {
                        Text("Uses Non-Exempt Encryption")
                        Spacer()
                        Image(systemName: enc ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(enc ? .orange : .secondary)
                    }
                }
            } header: {
                Text("Options")
            }
        }
    }

    // MARK: - Beta Groups Section

    @ViewBuilder
    private func buildBetaGroupsSection() -> some View {
        if !viewModel.uiState.betaGroups.isEmpty {
            Section {
                ForEach(viewModel.uiState.betaGroups) { group in
                    HStack(spacing: 12) {
                        Image(systemName: group.isInternalGroup ? "lock.fill" : "globe")
                            .foregroundStyle(group.isInternalGroup ? .blue : .green)
                        VStack(alignment: .leading) {
                            Text(group.name)
                            Text(group.isInternalGroup ? String(localized: "Internal") : String(localized: "External"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                HStack {
                    Text("Beta Groups")
                    Spacer()
                    Text("\(viewModel.uiState.betaGroups.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - What to Test Section

    @ViewBuilder
    private func buildWhatToTestSection() -> some View {
        if !viewModel.uiState.localizations.isEmpty {
            Section {
                ForEach(viewModel.uiState.localizations) { loc in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(loc.locale)
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)
                        Text(loc.whatsNew?.isEmpty == false ? loc.whatsNew! : String(localized: "(empty)"))
                            .font(.body)
                            .foregroundStyle(loc.whatsNew?.isEmpty == false ? .primary : .tertiary)
                    }
                    .padding(.vertical, 2)
                }
            } header: {
                Text("What to Test")
            }
        }
    }

    // MARK: - Actions Section

    @ViewBuilder
    private func buildActionsSection() -> some View {
        if !viewModel.uiState.build.isExpired
            && viewModel.uiState.account.canDelete(.testFlight) {
            Section {
                Button(role: .destructive) {
                    viewModel.uiState.showExpireConfirm = true
                } label: {
                    Label(String(localized: "Expire Build"), systemImage: "clock.badge.xmark")
                }
            } footer: {
                Text("Expiring a build immediately prevents testers from installing it. This cannot be undone via the API.")
            }
        }
    }

    // MARK: - Row Helper

    private func buildInfoRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }

    // MARK: - Helpers

    private func formatDateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func processingLabel(_ state: String) -> String {
        switch state {
        case "VALID":      return String(localized: "Ready")
        case "PROCESSING": return String(localized: "Processing")
        case "FAILED":     return String(localized: "Failed")
        case "INVALID":    return String(localized: "Invalid")
        default:           return state
        }
    }

    private func externalStateLabel(_ state: String) -> String {
        switch state {
        case "PROCESSING":                  return String(localized: "Processing")
        case "PROCESSING_EXCEPTION":        return String(localized: "Failed")
        case "MISSING_EXPORT_COMPLIANCE":   return String(localized: "Missing Export Compliance")
        case "READY_FOR_BETA_SUBMISSION":   return String(localized: "Ready to Submit")
        case "IN_EXPORT_COMPLIANCE_REVIEW": return String(localized: "Compliance Review")
        case "WAITING_FOR_BETA_REVIEW":     return String(localized: "Waiting Review")
        case "IN_BETA_REVIEW":              return String(localized: "In Review")
        case "BETA_REJECTED":               return String(localized: "Rejected")
        case "BETA_APPROVED":               return String(localized: "Approved")
        case "READY_FOR_BETA_TESTING":      return String(localized: "Ready for Testing")
        case "IN_BETA_TESTING":             return String(localized: "Testing")
        case "EXPIRED":                     return String(localized: "Expired")
        default:                            return state
        }
    }

    private func betaReviewLabel(_ state: String) -> String {
        switch state {
        case "WAITING_FOR_REVIEW": return String(localized: "Waiting Review")
        case "IN_REVIEW":          return String(localized: "In Review")
        case "REJECTED":           return String(localized: "Rejected")
        case "APPROVED":           return String(localized: "Approved")
        default:                   return state
        }
    }

    private func audienceLabel(_ audience: String) -> String {
        switch audience {
        case "INTERNAL_ONLY":      return String(localized: "Internal Only")
        case "APP_STORE_ELIGIBLE": return String(localized: "App Store Eligible")
        default:                   return audience
        }
    }
}
