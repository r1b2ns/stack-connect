import SwiftUI

// MARK: - Factory

@MainActor
struct ReviewDetailViewFactory {
    static func build(review: CustomerReviewModel, account: AccountModel) -> some View {
        ReviewDetailEntryView(review: review, account: account)
    }
}

// MARK: - Entry

private struct ReviewDetailEntryView: View {
    let review: CustomerReviewModel
    let account: AccountModel

    @StateObject private var viewModel: ReviewDetailViewModel

    init(review: CustomerReviewModel, account: AccountModel) {
        self.review = review
        self.account = account
        _viewModel = StateObject(wrappedValue: ReviewDetailViewModel(review: review, account: account))
    }

    var body: some View {
        ReviewDetailView(viewModel: viewModel)
    }
}

// MARK: - Protocol

@MainActor
protocol ReviewDetailViewModelProtocol: ObservableObject {
    var uiState: ReviewDetailUiState { get set }
    func submitReply(body: String) async
    func deleteResponse() async
    func startEditingReply()
    func cancelReplySheet()
}

// MARK: - UiState

struct ReviewDetailUiState {
    var review: CustomerReviewModel
    var account: AccountModel
    var isSending = false
    var toastMessage: ToastMessage?
    var showReplySheet = false
    var replyText = ""
    var isEditingReply = false
    var confirmDeleteResponse = false
}

// MARK: - ViewModel

@MainActor
final class ReviewDetailViewModel: ReviewDetailViewModelProtocol {

    @Published var uiState: ReviewDetailUiState

    private let keychain: KeyStorable

    init(
        review: CustomerReviewModel,
        account: AccountModel,
        keychain: KeyStorable = KeychainStorable.shared
    ) {
        self.uiState = ReviewDetailUiState(review: review, account: account)
        self.keychain = keychain
    }

    func submitReply(body: String) async {
        uiState.isSending = true

        do {
            guard let credentials: AppleCredentials = keychain.object(forKey: "credentials.\(uiState.account.id)") else {
                uiState.isSending = false
                return
            }

            let connection = AppleAccountConnection(credentials: credentials)

            // The App Store Connect API has no PATCH for replies. Editing means deleting
            // the existing response and creating a new one with the updated text.
            if uiState.isEditingReply, let existingId = uiState.review.responseId {
                try await connection.deleteReviewResponse(responseId: existingId)
            }

            try await connection.replyToReview(reviewId: uiState.review.id, responseBody: body)

            uiState.review.responseBody = body
            uiState.review.responseState = "PENDING_PUBLISH"
            uiState.review.responseDate = Date()
            uiState.showReplySheet = false
            uiState.replyText = ""
            let wasEditing = uiState.isEditingReply
            uiState.isEditingReply = false
            uiState.toastMessage = ToastMessage(
                wasEditing ? String(localized: "Reply updated") : String(localized: "Reply sent"),
                icon: "paperplane.fill"
            )
        } catch {
            uiState.toastMessage = ToastMessage(String(localized: "Failed to send reply"), icon: "exclamationmark.triangle.fill")
        }

        uiState.isSending = false
    }

    func startEditingReply() {
        uiState.replyText = uiState.review.responseBody ?? ""
        uiState.isEditingReply = true
        uiState.showReplySheet = true
    }

    func cancelReplySheet() {
        uiState.showReplySheet = false
        uiState.replyText = ""
        uiState.isEditingReply = false
    }

    func deleteResponse() async {
        guard let responseId = uiState.review.responseId else { return }

        do {
            guard let credentials: AppleCredentials = keychain.object(forKey: "credentials.\(uiState.account.id)") else { return }

            let connection = AppleAccountConnection(credentials: credentials)
            try await connection.deleteReviewResponse(responseId: responseId)

            uiState.review.responseId = nil
            uiState.review.responseBody = nil
            uiState.review.responseState = nil
            uiState.review.responseDate = nil
            uiState.toastMessage = ToastMessage(String(localized: "Reply deleted"), icon: "trash")
        } catch {
            uiState.toastMessage = ToastMessage(String(localized: "Failed to delete reply"), icon: "exclamationmark.triangle.fill")
        }
    }
}

// MARK: - View

struct ReviewDetailView<ViewModel: ReviewDetailViewModelProtocol>: View {

    @StateObject var viewModel: ViewModel

    var body: some View {
        List {
            buildReviewSection()
            buildResponseSection()
        }
        .navigationTitle(String(localized: "Review"))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $viewModel.uiState.showReplySheet) {
            buildReplySheet()
        }
        .alert(
            String(localized: "Delete Reply"),
            isPresented: $viewModel.uiState.confirmDeleteResponse
        ) {
            Button(String(localized: "Delete"), role: .destructive) {
                Task { await viewModel.deleteResponse() }
            }
            Button(String(localized: "Cancel"), role: .cancel) {}
        } message: {
            Text("Are you sure you want to delete your reply? This action cannot be undone.")
        }
        .toast(message: $viewModel.uiState.toastMessage)
    }

    // MARK: - Review Section

    private func buildReviewSection() -> some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                // Rating + date
                HStack {
                    HStack(spacing: 2) {
                        ForEach(1...5, id: \.self) { star in
                            Image(systemName: star <= viewModel.uiState.review.rating ? "star.fill" : "star")
                                .font(.body)
                                .foregroundStyle(.yellow)
                        }
                    }

                    Spacer()

                    if let date = viewModel.uiState.review.createdDate {
                        Text(formatDate(date))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                // Title
                if let title = viewModel.uiState.review.title, !title.isEmpty {
                    Text(title)
                        .font(.headline)
                }

                // Body
                if let body = viewModel.uiState.review.body, !body.isEmpty {
                    Text(body)
                        .font(.body)
                        .foregroundStyle(.secondary)
                }

                // Metadata
                HStack(spacing: 12) {
                    if let nickname = viewModel.uiState.review.reviewerNickname {
                        Label(nickname, systemImage: "person.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let territory = viewModel.uiState.review.territory {
                        Label(
                            Locale.current.localizedString(forRegionCode: territory) ?? territory,
                            systemImage: "globe"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.vertical, 4)
        } header: {
            Text("Customer Review")
        }
    }

    // MARK: - Response Section

    @ViewBuilder
    private func buildResponseSection() -> some View {
        if let responseBody = viewModel.uiState.review.responseBody, !responseBody.isEmpty {
            Section {
                Button {
                    if viewModel.uiState.account.canEdit(.review) {
                        viewModel.startEditingReply()
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label(String(localized: "Developer Response"), systemImage: "arrowshape.turn.up.left.fill")
                                .font(.subheadline)
                                .fontWeight(.medium)

                            Spacer()

                            if let state = viewModel.uiState.review.responseState {
                                Text(state == "PUBLISHED" ? String(localized: "Published") : String(localized: "Pending"))
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundStyle(state == "PUBLISHED" ? Color.green : Color.orange)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background((state == "PUBLISHED" ? Color.green : Color.orange).opacity(0.12))
                                    .clipShape(Capsule())
                            }
                        }

                        Text(responseBody)
                            .font(.body)
                            .foregroundStyle(.secondary)

                        if let date = viewModel.uiState.review.responseDate {
                            Text(formatDate(date))
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .disabled(!viewModel.uiState.account.canEdit(.review))
            } header: {
                Text("Your Reply")
            } footer: {
                if viewModel.uiState.account.canEdit(.review) {
                    Text("Tap to edit your reply.")
                }
            }

            if viewModel.uiState.account.canDelete(.review) {
                Section {
                    Button(role: .destructive) {
                        viewModel.uiState.confirmDeleteResponse = true
                    } label: {
                        Label(String(localized: "Delete Reply"), systemImage: "trash")
                    }
                }
            }
        } else {
            if viewModel.uiState.account.canEdit(.review) {
                Section {
                    Button {
                        viewModel.uiState.showReplySheet = true
                    } label: {
                        Label(String(localized: "Write a Reply"), systemImage: "arrowshape.turn.up.left.fill")
                    }
                } footer: {
                    Text("Reply to this review. Your response will be visible on the App Store.")
                }
            }
        }
    }

    // MARK: - Reply Sheet

    private func buildReplySheet() -> some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $viewModel.uiState.replyText)
                        .frame(minHeight: 150)
                } header: {
                    Text("Your Reply")
                } footer: {
                    Text("Your reply will be visible to all users on the App Store.")
                }
            }
            .navigationTitle(viewModel.uiState.isEditingReply
                ? String(localized: "Edit Reply")
                : String(localized: "Reply to Review"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) {
                        viewModel.cancelReplySheet()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if viewModel.uiState.isSending {
                        ProgressView()
                    } else {
                        Button(viewModel.uiState.isEditingReply
                            ? String(localized: "Save")
                            : String(localized: "Send")
                        ) {
                            Task { await viewModel.submitReply(body: viewModel.uiState.replyText) }
                        }
                        .disabled(viewModel.uiState.replyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            .disabled(viewModel.uiState.isSending)
        }
    }

    // MARK: - Helpers

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
