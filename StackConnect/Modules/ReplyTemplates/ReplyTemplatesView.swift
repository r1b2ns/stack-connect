import SwiftUI

// MARK: - Factory

@MainActor
struct ReplyTemplatesViewFactory {
    /// - Parameters:
    ///   - accountId: Templates are scoped per account; only this account's are listed.
    ///   - onSelect: Called when the user taps a template. The caller owns the
    ///     dismissal + pre-fill of the reply composer.
    static func build(
        accountId: String,
        onSelect: @escaping (ReplyTemplateModel) -> Void
    ) -> some View {
        ReplyTemplatesEntryView(accountId: accountId, onSelect: onSelect)
    }
}

// MARK: - Entry

private struct ReplyTemplatesEntryView: View {

    private let onSelect: (ReplyTemplateModel) -> Void

    @StateObject private var viewModel: ReplyTemplatesViewModel

    init(accountId: String, onSelect: @escaping (ReplyTemplateModel) -> Void) {
        self.onSelect = onSelect
        _viewModel = StateObject(wrappedValue: ReplyTemplatesViewModel(accountId: accountId))
    }

    var body: some View {
        ReplyTemplatesView(viewModel: viewModel, onSelect: onSelect)
    }
}

// MARK: - View

/// Bottom-sheet list of the account's saved reply templates.
///
/// This module has no coordinator: it is a single list plus one leaf form, both
/// presented within the sheet, so there is no navigation graph to own. That
/// mirrors `ReviewDetailView`, its closest sibling, which is likewise
/// sheet-driven rather than coordinator-driven.
struct ReplyTemplatesView<ViewModel: ReplyTemplatesViewModelProtocol>: View {

    @ObservedObject var viewModel: ViewModel
    let onSelect: (ReplyTemplateModel) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            buildContent()
                .navigationTitle(String(localized: "Reply Templates"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(String(localized: "Done")) { dismiss() }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            viewModel.uiState.form = .create
                        } label: {
                            Image(systemName: "plus")
                        }
                        .accessibilityLabel(String(localized: "New Template"))
                    }
                }
                .sheet(item: $viewModel.uiState.form) { mode in
                    buildFormSheet(mode: mode)
                }
                .toast(message: $viewModel.uiState.toastMessage)
        }
        .task { await viewModel.load() }
    }

    // MARK: - Content

    @ViewBuilder
    private func buildContent() -> some View {
        if viewModel.uiState.isLoading && viewModel.uiState.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.uiState.isEmpty {
            buildEmptyState()
        } else {
            buildList()
        }
    }

    private func buildEmptyState() -> some View {
        ContentUnavailableView {
            Label(String(localized: "No Templates"), systemImage: "text.bubble")
        } description: {
            Text("Save replies you use often and reuse them with a tap.")
        } actions: {
            Button(String(localized: "New Template")) {
                viewModel.uiState.form = .create
            }
        }
    }

    private func buildList() -> some View {
        List {
            Section {
                ForEach(viewModel.uiState.templates) { template in
                    Button {
                        onSelect(template)
                    } label: {
                        buildRow(template)
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            Task { await viewModel.delete(template) }
                        } label: {
                            Label(String(localized: "Delete"), systemImage: "trash")
                        }

                        Button {
                            viewModel.uiState.form = .edit(template)
                        } label: {
                            Label(String(localized: "Edit"), systemImage: "pencil")
                        }
                        .tint(.blue)
                    }
                }
            } footer: {
                Text("Tap a template to use it. Swipe a row to edit or delete it.")
            }
        }
    }

    private func buildRow(_ template: ReplyTemplateModel) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(template.title)
                .font(.headline)

            Text(template.body)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    // MARK: - Form Sheet

    private func buildFormSheet(mode: ReplyTemplateFormMode) -> some View {
        ReplyTemplateFormView(mode: mode) { title, body in
            Task {
                switch mode {
                case .create:
                    await viewModel.save(title: title, body: body)
                case .edit(let template):
                    await viewModel.update(template, title: title, body: body)
                }
            }
        }
    }
}
