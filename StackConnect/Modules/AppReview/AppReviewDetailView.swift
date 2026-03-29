import SwiftUI

// MARK: - Factory

struct AppReviewDetailViewFactory {
    static func build(submission: ReviewSubmissionModel, account: AccountModel) -> some View {
        AppReviewDetailEntry(submission: submission, account: account)
    }
}

// MARK: - Entry

private struct AppReviewDetailEntry: View {
    let submission: ReviewSubmissionModel
    let account: AccountModel

    @StateObject private var viewModel: AppReviewDetailViewModel

    init(submission: ReviewSubmissionModel, account: AccountModel) {
        self.submission = submission
        self.account = account
        _viewModel = StateObject(wrappedValue: AppReviewDetailViewModel(submission: submission, account: account))
    }

    var body: some View {
        AppReviewDetailView(viewModel: viewModel)
    }
}

// MARK: - View

struct AppReviewDetailView<ViewModel: AppReviewDetailViewModelProtocol>: View {

    @ObservedObject var viewModel: ViewModel

    var body: some View {
        List {
            buildSubmissionSection()
            buildResolutionCenterBanner()

            if viewModel.uiState.isLoading {
                Section {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                    .padding(.vertical, 8)
                }
            } else if let detail = viewModel.uiState.reviewDetail {
                buildContactSection(detail)
                buildDemoAccountSection(detail)
                buildNotesSection(detail)
            }
        }
        .navigationTitle(String(localized: "Submission Detail"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.loadDetail() }
    }

    // MARK: - Submission Info

    private func buildSubmissionSection() -> some View {
        Section {
            buildDetailRow(
                icon: "tag.fill",
                color: .blue,
                title: String(localized: "Version"),
                value: viewModel.uiState.submission.versionString ?? "–"
            )

            buildDetailRow(
                icon: "calendar",
                color: .orange,
                title: String(localized: "Date"),
                value: formatDate(viewModel.uiState.submission.submittedDate)
            )

            buildDetailRow(
                icon: "person.fill",
                color: .purple,
                title: String(localized: "Submitted By"),
                value: buildActorValue()
            )

            buildDetailRow(
                icon: "iphone",
                color: .gray,
                title: String(localized: "Platform"),
                value: viewModel.uiState.submission.platformDisplayName
            )

            buildStatusRow()

        } header: {
            Text("Submission")
        }
    }

    private func buildStatusRow() -> some View {
        HStack {
            Image(systemName: "checkmark.shield.fill")
                .font(.body)
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(stateColor(viewModel.uiState.submission.stateColor))
                .clipShape(RoundedRectangle(cornerRadius: 7))

            Text(String(localized: "Status"))
                .font(.body)

            Spacer()

            Text(viewModel.uiState.submission.stateDisplayName)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(stateColor(viewModel.uiState.submission.stateColor))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(stateColor(viewModel.uiState.submission.stateColor).opacity(0.12))
                .clipShape(Capsule())
        }
    }

    // MARK: - Resolution Center Banner

    private func buildResolutionCenterBanner() -> some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(.blue)
                        .font(.title3)

                    Text("Messages exchanged with App Review are only available in the App Store Connect Resolution Center.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Link(destination: URL(string: "https://appstoreconnect.apple.com/apps/\(viewModel.uiState.submission.appId)/appstore/resolutioncenter")!) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.up.right.square.fill")
                        Text(String(localized: "Open Resolution Center"))
                            .fontWeight(.medium)
                    }
                    .font(.subheadline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.blue.opacity(0.1))
                    .foregroundStyle(.blue)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Contact Section

    @ViewBuilder
    private func buildContactSection(_ detail: AppReviewDetailModel) -> some View {
        let hasContact = detail.contactFirstName != nil || detail.contactLastName != nil
            || detail.contactEmail != nil || detail.contactPhone != nil

        if hasContact {
            Section {
                let fullName = [detail.contactFirstName, detail.contactLastName]
                    .compactMap { $0 }
                    .joined(separator: " ")

                if !fullName.isEmpty {
                    buildDetailRow(
                        icon: "person.fill",
                        color: .blue,
                        title: String(localized: "Name"),
                        value: fullName
                    )
                }
                if let email = detail.contactEmail {
                    buildDetailRow(
                        icon: "envelope.fill",
                        color: .blue,
                        title: String(localized: "Email"),
                        value: email
                    )
                }
                if let phone = detail.contactPhone {
                    buildDetailRow(
                        icon: "phone.fill",
                        color: .green,
                        title: String(localized: "Phone"),
                        value: phone
                    )
                }
            } header: {
                Text("Contact Information")
            }
        }
    }

    // MARK: - Demo Account Section

    @ViewBuilder
    private func buildDemoAccountSection(_ detail: AppReviewDetailModel) -> some View {
        let hasDemo = detail.demoAccountName != nil || detail.demoAccountPassword != nil
            || detail.isDemoAccountRequired != nil

        if hasDemo {
            Section {
                if let required = detail.isDemoAccountRequired {
                    HStack {
                        Image(systemName: "person.badge.key.fill")
                            .font(.body)
                            .foregroundStyle(.white)
                            .frame(width: 32, height: 32)
                            .background(Color.indigo)
                            .clipShape(RoundedRectangle(cornerRadius: 7))

                        Text(String(localized: "Required"))
                            .font(.body)

                        Spacer()

                        Text(required ? String(localized: "Yes") : String(localized: "No"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                if let name = detail.demoAccountName {
                    buildDetailRow(
                        icon: "person.fill",
                        color: .indigo,
                        title: String(localized: "Username"),
                        value: name
                    )
                }

                if let password = detail.demoAccountPassword {
                    buildDetailRow(
                        icon: "lock.fill",
                        color: .indigo,
                        title: String(localized: "Password"),
                        value: password
                    )
                }
            } header: {
                Text("Demo Account")
            }
        }
    }

    // MARK: - Notes Section

    @ViewBuilder
    private func buildNotesSection(_ detail: AppReviewDetailModel) -> some View {
        if let notes = detail.notes, !notes.isEmpty {
            Section {
                Text(notes)
                    .font(.body)
                    .foregroundStyle(.primary)
            } header: {
                Text("Notes for Reviewer")
            }
        }
    }

    // MARK: - Reusable Row

    private func buildDetailRow(icon: String, color: Color, title: String, value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(color)
                .clipShape(RoundedRectangle(cornerRadius: 7))

            Text(title)
                .font(.body)

            Spacer()

            Text(value)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }

    // MARK: - Helpers

    private func buildActorValue() -> String {
        let submission = viewModel.uiState.submission
        if let name = submission.submittedByName {
            if let email = submission.submittedByEmail {
                return "\(name) (\(email))"
            }
            return name
        }
        return "–"
    }

    private func formatDate(_ date: Date?) -> String {
        guard let date else { return "–" }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM, EEE, HH:mm"
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
