import SwiftUI

/// Full-width prominent sign-in button for a Form row:
/// `{glyph} {title}`, or a spinner with the title while `isLoading`.
///
/// Used by Add Account for "Sign in with Google". Tracking belongs to the
/// caller (`action` is where it sends `button_tap`).
struct StackSignInButton: View {

    let title: String
    var systemImage: String = "person.crop.circle.badge.checkmark"
    var isLoading: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: systemImage)
                        .accessibilityHidden(true)
                }
                Text(title)
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.borderedProminent)
        .disabled(isLoading)
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        .listRowBackground(Color.clear)
    }
}

#Preview {
    Form {
        Section {
            StackSignInButton(title: "Sign in with Google") {}
        }
        Section {
            StackSignInButton(title: "Signing in…", isLoading: true) {}
        }
    }
}
