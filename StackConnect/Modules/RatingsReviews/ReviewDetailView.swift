import SwiftUI
import StackProtocols

// MARK: - Factory

/// One review with the reply composer and reply templates, for any store: the
/// store comes from the account (`CustomerReviewsServiceFactory`).
@MainActor
struct ReviewDetailViewFactory {
    /// - Parameter appId: the review's app (package name for Google Play), when
    ///   known, so a reply also updates that app's offline reviews cache.
    static func build(review: CustomerReviewModel, appName: String, account: AccountModel, appId: String? = nil) -> some View {
        ReviewDetailEntryView(review: review, appName: appName, account: account, appId: appId)
    }
}

// MARK: - Entry

private struct ReviewDetailEntryView: View {
    let review: CustomerReviewModel
    let appName: String
    let account: AccountModel

    @StateObject private var viewModel: ReviewDetailViewModel

    init(review: CustomerReviewModel, appName: String, account: AccountModel, appId: String?) {
        self.review = review
        self.appName = appName
        self.account = account
        _viewModel = StateObject(wrappedValue: ReviewDetailViewModel(
            review: review,
            appName: appName,
            account: account,
            service: CustomerReviewsServiceFactory.makeService(for: account),
            cache: appId.flatMap { CustomerReviewsServiceFactory.makeCache(for: account, appId: $0) }
        ))
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
    func selectTemplate(_ template: ReplyTemplateModel)
    func applyPendingTemplate()
    /// Loads the account's reply templates for the inline composer's chips.
    func loadTemplates() async
    /// Inline composer (regular width): fills the draft with a template.
    func insertTemplate(_ template: ReplyTemplateModel)
    /// Inline composer (regular width): edits the current reply in place,
    /// without the composer sheet.
    func beginInlineEdit()
}

// MARK: - UiState

struct ReviewDetailUiState {
    var review: CustomerReviewModel
    var appName: String
    var account: AccountModel
    /// What the account's store supports (reply deletion, copy, reply limit).
    var traits: CustomerReviewsTraits
    var isSending = false
    var toastMessage: ToastMessage?
    var showReplySheet = false
    var replyText = ""
    /// Last reply failure, shown inside the reply composer.
    var replyError: String?
    var isEditingReply = false
    var confirmDeleteResponse = false
    var showTemplatesSheet = false
    /// Body of a template picked in the templates sheet, held until that sheet
    /// has finished dismissing. SwiftUI cannot present two sheets from the same
    /// view at once, so the reply composer is only opened from the templates
    /// sheet's `onDismiss`. See `selectTemplate` / `applyPendingTemplate`.
    var pendingTemplateBody: String?
    /// The account's reply templates (inline composer chips, regular width).
    var templates: [ReplyTemplateModel] = []

    /// The inline composer can send: there is text and nothing in flight.
    var canSendReply: Bool {
        canReply && !isSending && !replyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The inline composer shows while there is no reply yet, or while the
    /// existing one is being edited.
    var showsInlineComposer: Bool {
        guard canReply else { return false }
        let hasReply = !(review.responseBody ?? "").isEmpty
        return !hasReply || isEditingReply
    }

    /// Writing or editing a reply is gated by the account's `review` rules (edit),
    /// for every store.
    var canReply: Bool {
        account.canEdit(.review)
    }

    /// Needs the account's `review` delete rule and a store that can delete
    /// replies (Google Play can't: a reply can only be replaced).
    var canDeleteReply: Bool {
        traits.canDeleteReplies && account.canDelete(.review)
    }

    /// Plain-text payload for the system share sheet.
    var shareText: String {
        let stars = String(repeating: "★", count: review.rating) + String(repeating: "☆", count: max(0, 5 - review.rating))
        let date = review.createdDate.map(ReviewShareTextFormatter.format(date:)) ?? "–"
        let territory = review.territory.map { Locale.current.localizedString(forRegionCode: $0) ?? $0 } ?? "–"
        let user = review.reviewerNickname ?? "–"
        let title = review.title ?? "–"
        let description = review.body ?? "–"
        let separator = String(repeating: "-", count: 30)

        var text = """
        
        App: \(appName)
        User: \(user)
        date: \(date)
        stars: \(stars) (\(review.rating)/5)
        Country: \(territory)
        \(separator)
        Title: 
        \(title)
        
        Description: 
        \(description)
        """

        if let response = review.responseBody, !response.isEmpty {
            text += "\n\(separator)\n\nAnswer: \(response)"
        }

        return text
    }
}

// MARK: - Date Formatter

enum ReviewShareTextFormatter {
    static func format(date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - ViewModel

@MainActor
final class ReviewDetailViewModel: ReviewDetailViewModelProtocol {

    @Published var uiState: ReviewDetailUiState

    private let service: (any CustomerReviewsServicing)?
    private let cache: (any CustomerReviewsCaching)?
    private let analytics: AnalyticsTracking
    private let templatesStorage: PersistentStorable?

    /// - Parameters:
    ///   - service: the account's reviews backend; `nil` when its credentials
    ///     are missing (sending then does nothing).
    ///   - cache: the app's offline reviews cache, kept in step after a reply.
    init(
        review: CustomerReviewModel,
        appName: String,
        account: AccountModel,
        service: (any CustomerReviewsServicing)?,
        cache: (any CustomerReviewsCaching)? = nil,
        analytics: AnalyticsTracking = AnalyticsService.shared,
        templatesStorage: PersistentStorable? = nil
    ) {
        self.uiState = ReviewDetailUiState(
            review: review,
            appName: appName,
            account: account,
            traits: service?.traits ?? .appStore
        )
        self.service = service
        self.cache = cache
        self.analytics = analytics
        self.templatesStorage = templatesStorage ?? SwiftDataStorable.shared
    }

    func submitReply(body: String) async {
        // Editing replaces the existing reply; a new reply creates one.
        let action: AnalyticsAction = uiState.isEditingReply ? .updateReviewReply : .replyToReview
        analytics.track(.buttonTap(uiState.isEditingReply ? .save : .send, on: .reviewReply))
        guard uiState.canReply else {
            uiState.toastMessage = ToastMessage(
                String(localized: "This account doesn't have permission to reply to reviews."),
                icon: "exclamationmark.triangle.fill"
            )
            return
        }
        guard let service else {
            analytics.track(.action(action, on: .reviewReply, result: .failure))
            return
        }

        uiState.isSending = true
        uiState.replyError = nil
        // Read before the call: the composer may be dismissed meanwhile.
        let isEditing = uiState.isEditingReply
        let reviewId = uiState.review.id

        do {
            // Editing replaces the current reply; how is up to the store (App
            // Store Connect deletes and re-creates it, Google Play upserts).
            let replacingId = isEditing ? uiState.review.responseId : nil
            let response = try await service.reply(
                toReviewId: reviewId,
                body: body,
                replacingResponseId: replacingId
            )

            uiState.review.applyResponse(response)
            uiState.showReplySheet = false
            uiState.replyText = ""
            uiState.isEditingReply = false
            uiState.toastMessage = ToastMessage(
                isEditing ? String(localized: "Reply updated") : String(localized: "Reply sent"),
                icon: "paperplane.fill"
            )
            await cache?.saveResponse(response, forReviewId: reviewId)
            analytics.track(.action(action, on: .reviewReply, result: .success))
        } catch {
            analytics.track(.action(action, on: .reviewReply, result: .failure))
            let message = service.message(for: error, operation: .reply)
            uiState.replyError = message
            uiState.toastMessage = ToastMessage(message, icon: "exclamationmark.triangle.fill")
            Log.print.error("[ReviewDetail] Reply failed: \(error.localizedDescription)")
        }

        uiState.isSending = false
    }

    func startEditingReply() {
        uiState.replyText = uiState.review.responseBody ?? ""
        uiState.isEditingReply = true
        uiState.showReplySheet = true
    }

    /// Closes the composer and drops its draft, error and edit mode. Also runs
    /// when the sheet is swiped away, so the next reply starts clean.
    func cancelReplySheet() {
        uiState.showReplySheet = false
        uiState.replyText = ""
        uiState.replyError = nil
        uiState.isEditingReply = false
    }

    /// Step 1 of the templates → composer handoff: record the pick and close the
    /// templates sheet. Opening the composer here would be a no-op, because the
    /// templates sheet is still presented from the same view.
    func selectTemplate(_ template: ReplyTemplateModel) {
        uiState.pendingTemplateBody = template.body
        uiState.showTemplatesSheet = false
    }

    /// Step 2, invoked from the templates sheet's `onDismiss` (i.e. once no sheet
    /// is presented): pre-fill the composer and open it. No-ops when the sheet was
    /// dismissed without a pick (swipe-down / Done).
    func applyPendingTemplate() {
        guard let body = uiState.pendingTemplateBody else { return }
        uiState.pendingTemplateBody = nil
        uiState.replyText = body
        uiState.isEditingReply = false
        uiState.showReplySheet = true
    }

    // MARK: - Inline Composer

    func loadTemplates() async {
        guard let templatesStorage else { return }
        do {
            let all: [ReplyTemplateModel] = try await templatesStorage.fetchAll(ReplyTemplateModel.self)
            uiState.templates = all
                .filter { $0.accountId == uiState.account.id }
                .sorted { $0.updatedAt > $1.updatedAt }
        } catch {
            Log.print.error("[ReviewDetail] Failed to load reply templates: \(error.localizedDescription)")
            uiState.templates = []
        }
    }

    func insertTemplate(_ template: ReplyTemplateModel) {
        analytics.track(.buttonTap(.replyTemplates, on: .reviewDetail))
        uiState.replyText = template.body
        uiState.replyError = nil
    }

    func beginInlineEdit() {
        uiState.replyText = uiState.review.responseBody ?? ""
        uiState.replyError = nil
        uiState.isEditingReply = true
    }

    func deleteResponse() async {
        analytics.track(.buttonTap(.confirmDelete, on: .reviewDetail))
        guard uiState.canDeleteReply, let responseId = uiState.review.responseId else { return }
        guard let service else {
            analytics.track(.action(.deleteReviewResponse, on: .reviewDetail, result: .failure))
            return
        }

        do {
            try await service.deleteReply(responseId: responseId)

            uiState.review.responseId = nil
            uiState.review.responseBody = nil
            uiState.review.responseState = nil
            uiState.review.responseDate = nil
            uiState.toastMessage = ToastMessage(String(localized: "Reply deleted"), icon: "trash")
            analytics.track(.action(.deleteReviewResponse, on: .reviewDetail, result: .success))
        } catch {
            analytics.track(.action(.deleteReviewResponse, on: .reviewDetail, result: .failure))
            uiState.toastMessage = ToastMessage(
                service.message(for: error, operation: .deleteReply),
                icon: "exclamationmark.triangle.fill"
            )
            Log.print.error("[ReviewDetail] Delete reply failed: \(error.localizedDescription)")
        }
    }
}

// MARK: - View

struct ReviewDetailView<ViewModel: ReviewDetailViewModelProtocol>: View {

    @StateObject var viewModel: ViewModel
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    /// Regular width (iPad detail column, Mac window): the reply is written
    /// inline under the review, with the templates as chips; compact keeps the
    /// composer and templates sheets.
    private var isRegular: Bool {
        horizontalSizeClass == .regular
    }

    var body: some View {
        List {
            buildReviewSection()
            if isRegular {
                buildRegularResponseSections()
            } else {
                buildResponseSection()
            }
        }
        .task {
            if isRegular {
                await viewModel.loadTemplates()
            }
        }
        .navigationTitle(String(localized: "Review"))
        .trackScreen(.reviewDetail)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                ShareLink(
                    item: viewModel.uiState.shareText,
                    subject: Text("Review – \(viewModel.uiState.appName)\n"),
                    message: Text(viewModel.uiState.appName)
                ) {
                    Image(systemName: "square.and.arrow.up")
                }
            }
        }
        .sheet(
            isPresented: $viewModel.uiState.showReplySheet,
            // Swiping the composer away drops its draft, error and edit mode too.
            onDismiss: { viewModel.cancelReplySheet() }
        ) {
            buildReplySheet()
        }
        .sheet(
            isPresented: $viewModel.uiState.showTemplatesSheet,
            // Runs once the templates sheet is fully dismissed, which is the only
            // point at which the composer sheet can be presented from this view.
            onDismiss: { viewModel.applyPendingTemplate() }
        ) {
            ReplyTemplatesViewFactory.build(
                accountId: viewModel.uiState.account.id,
                onSelect: { template in viewModel.selectTemplate(template) }
            )
            .presentationDetents([.medium, .large])
        }
        .alert(
            String(localized: "Delete Reply"),
            isPresented: $viewModel.uiState.confirmDeleteResponse
        ) {
            Button(String(localized: "Delete"), role: .destructive) {
                Task { await viewModel.deleteResponse() }
            }
            StackTrackedButton(String(localized: "Cancel"), button: .cancel, on: .reviewDetail, role: .cancel) {}
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
                HStack(spacing: 4) {
                    if let nickname = viewModel.uiState.review.reviewerNickname {
                        Group {
                            Image(systemName: "person.fill")
                            Text(nickname)
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    Spacer().frame(width: 8)
                    if let territory = viewModel.uiState.review.territory {
                        Group {
                            Image(systemName: "globe")
                            Text(Locale.current.localizedString(forRegionCode: territory) ?? territory)
                        }
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
                StackTrackedButton(.edit, on: .reviewDetail) {
                    if viewModel.uiState.canReply {
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
                .disabled(!viewModel.uiState.canReply)
            } header: {
                Text("Your Reply")
            } footer: {
                if viewModel.uiState.canReply {
                    Text("Tap to edit your reply.")
                }
            }

            if viewModel.uiState.canDeleteReply {
                Section {
                    StackTrackedButton(.delete, on: .reviewDetail, role: .destructive) {
                        viewModel.uiState.confirmDeleteResponse = true
                    } label: {
                        Label(String(localized: "Delete Reply"), systemImage: "trash")
                    }
                }
            }
        } else {
            if viewModel.uiState.canReply {
                Section {
                    StackTrackedButton(.reply, on: .reviewDetail) {
                        viewModel.uiState.showReplySheet = true
                    } label: {
                        Label(String(localized: "Write a Reply"), systemImage: "arrowshape.turn.up.left.fill")
                    }

                    StackTrackedButton(.replyTemplates, on: .reviewDetail) {
                        viewModel.uiState.showTemplatesSheet = true
                    } label: {
                        Label(String(localized: "Reply Templates"), systemImage: "text.bubble")
                    }
                } footer: {
                    Text(viewModel.uiState.traits.composeReplyNote)
                }
            }
        }
    }

    // MARK: - Regular Width Response

    @ViewBuilder
    private func buildRegularResponseSections() -> some View {
        let state = viewModel.uiState
        if let responseBody = state.review.responseBody, !responseBody.isEmpty, !state.isEditingReply {
            Section {
                buildResponseContent(responseBody)
            } header: {
                Text("Your Reply")
            }

            if state.canReply || state.canDeleteReply {
                Section {
                    if state.canReply {
                        StackTrackedButton(.edit, on: .reviewDetail) {
                            viewModel.beginInlineEdit()
                        } label: {
                            Label(String(localized: "Edit Reply"), systemImage: "pencil")
                        }
                    }
                    if state.canDeleteReply {
                        StackTrackedButton(.delete, on: .reviewDetail, role: .destructive) {
                            viewModel.uiState.confirmDeleteResponse = true
                        } label: {
                            Label(String(localized: "Delete Reply"), systemImage: "trash")
                        }
                    }
                }
            }
        }

        if state.showsInlineComposer {
            Section {
                StackInlineReplyComposer(
                    text: $viewModel.uiState.replyText,
                    confirmTitle: state.isEditingReply ? String(localized: "Save") : String(localized: "Send"),
                    footer: state.traits.replyVisibilityNote,
                    characterLimit: state.traits.replyCharacterLimit,
                    error: state.replyError,
                    templates: state.templates.map { .init(id: $0.id, title: $0.title) },
                    isSending: state.isSending,
                    canSend: state.canSendReply,
                    onSelectTemplate: { chip in
                        if let template = state.templates.first(where: { $0.id == chip.id }) {
                            viewModel.insertTemplate(template)
                        }
                    },
                    onSend: {
                        let body = viewModel.uiState.replyText
                        Task { await viewModel.submitReply(body: body) }
                    },
                    onCancel: state.isEditingReply ? { viewModel.cancelReplySheet() } : nil
                )
            } header: {
                Text(state.isEditingReply ? String(localized: "Edit Reply") : String(localized: "Your Reply"))
            }
        }
    }

    private func buildResponseContent(_ responseBody: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let state = viewModel.uiState.review.responseState {
                Text(state == "PUBLISHED" ? String(localized: "Published") : String(localized: "Pending"))
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(state == "PUBLISHED" ? Color.green : Color.orange)
            }
            Text(responseBody)
                .font(.body)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            if let date = viewModel.uiState.review.responseDate {
                Text(formatDate(date))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Reply Sheet

    private func buildReplySheet() -> some View {
        StackReplyComposer(
            title: viewModel.uiState.isEditingReply
                ? String(localized: "Edit Reply")
                : String(localized: "Reply to Review"),
            confirmTitle: viewModel.uiState.isEditingReply
                ? String(localized: "Save")
                : String(localized: "Send"),
            text: $viewModel.uiState.replyText,
            footer: viewModel.uiState.traits.replyVisibilityNote,
            characterLimit: viewModel.uiState.traits.replyCharacterLimit,
            error: viewModel.uiState.replyError,
            trackingScreen: .reviewReply,
            isSending: viewModel.uiState.isSending,
            onSend: { text in
                Task { await viewModel.submitReply(body: text) }
            },
            onCancel: {
                viewModel.cancelReplySheet()
            }
        )
    }

    // MARK: - Helpers

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
