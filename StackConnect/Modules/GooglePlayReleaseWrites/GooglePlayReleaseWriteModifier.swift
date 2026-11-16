import SwiftUI

/// Attaches the release write flow to a screen: the confirmation (plan R4),
/// the failure alert and the success toast.
struct GooglePlayReleaseWriteModifier<ViewModel: GooglePlayReleaseWriteViewModelProtocol>: ViewModifier {

    @ObservedObject var viewModel: ViewModel

    func body(content: Content) -> some View {
        content
            .alert(
                viewModel.uiState.pendingWrite?.title ?? "",
                isPresented: Binding(
                    get: { viewModel.uiState.pendingWrite != nil },
                    set: { if !$0 { viewModel.cancelPendingWrite() } }
                ),
                presenting: viewModel.uiState.pendingWrite
            ) { write in
                Button(write.confirmLabel, role: write.isDestructive ? .destructive : nil) {
                    Task { await viewModel.confirm(write) }
                }
                Button(String(localized: "Cancel"), role: .cancel) {
                    viewModel.cancelPendingWrite()
                }
            } message: { write in
                Text(write.message)
            }
            .alert(
                String(localized: "Couldn't Change the Release"),
                isPresented: Binding(
                    get: { viewModel.uiState.errorMessage != nil },
                    set: { if !$0 { viewModel.uiState.errorMessage = nil } }
                )
            ) {
                Button(String(localized: "OK"), role: .cancel) {
                    viewModel.uiState.errorMessage = nil
                }
            } message: {
                Text(viewModel.uiState.errorMessage ?? "")
            }
            .overlay {
                if viewModel.uiState.isWriting {
                    ProgressView()
                        .padding(20)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                }
            }
            .toast(message: $viewModel.uiState.toastMessage)
    }
}

extension View {
    func googlePlayReleaseWrites<ViewModel: GooglePlayReleaseWriteViewModelProtocol>(_ viewModel: ViewModel) -> some View {
        modifier(GooglePlayReleaseWriteModifier(viewModel: viewModel))
    }
}

// MARK: - Bar and swipe buttons

extension GooglePlayReleaseAction {

    var title: String {
        switch self {
        case .rollOut:         return String(localized: "Roll Out")
        case .increaseRollout: return String(localized: "Increase Rollout")
        case .halt:            return String(localized: "Halt Rollout")
        case .resume:          return String(localized: "Resume Rollout")
        case .releaseToAll:    return String(localized: "Release to All Users")
        case .promote:         return String(localized: "Promote")
        }
    }

    /// Short title for swipe actions.
    var shortTitle: String {
        switch self {
        case .rollOut:         return String(localized: "Roll Out")
        case .increaseRollout: return String(localized: "Increase")
        case .halt:            return String(localized: "Halt")
        case .resume:          return String(localized: "Resume")
        case .releaseToAll:    return String(localized: "Complete")
        case .promote:         return String(localized: "Promote")
        }
    }

    var icon: String {
        switch self {
        case .rollOut:         return "paperplane.fill"
        case .increaseRollout: return "chart.bar.fill"
        case .halt:            return "pause.circle.fill"
        case .resume:          return "play.circle.fill"
        case .releaseToAll:    return "person.3.fill"
        case .promote:         return "arrow.up.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .rollOut, .increaseRollout: return .blue
        case .halt:                      return .orange
        case .resume:                    return .blue
        case .releaseToAll, .promote:    return .green
        }
    }

    var writeKind: GooglePlayReleaseWriteAccess.Kind {
        self == .promote ? .add : .edit
    }
}

/// Bottom bar of a release (prototype screen 3), from `GooglePlayReleaseActions`:
/// Halt (outlined) next to Increase / Resume, then the full-width final action.
struct GooglePlayReleaseActionBar: View {

    let actions: [GooglePlayReleaseAction]
    let isBusy: Bool
    let perform: (GooglePlayReleaseAction) -> Void

    var body: some View {
        if !actions.isEmpty {
            StackActionBar(isBusy: isBusy) {
                VStack(spacing: 10) {
                    // Prototype order: Halt (outlined) first, then Increase / Resume.
                    let paired = [GooglePlayReleaseAction.halt, .increaseRollout, .resume].filter(actions.contains)
                    if !paired.isEmpty {
                        HStack(spacing: 10) {
                            ForEach(paired, id: \.self) { action in
                                button(action, style: action == .halt ? .outlined : .filled)
                            }
                        }
                    }
                    ForEach(actions.filter { !paired.contains($0) }, id: \.self) { action in
                        button(action, style: .filled)
                    }
                }
            }
        }
    }

    private func button(_ action: GooglePlayReleaseAction, style: StackActionButtonLabel.Style) -> some View {
        Button {
            perform(action)
        } label: {
            StackActionButtonLabel(title: action.title, color: action.color, style: style)
        }
        .buttonStyle(.plain)
    }
}
