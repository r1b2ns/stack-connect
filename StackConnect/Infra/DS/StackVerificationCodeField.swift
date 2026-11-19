import SwiftUI

/// A one-time code entry sized to the code: `length` boxes, one digit each,
/// over a single hidden text field (so paste, the keyboard's "From Messages"
/// suggestion and VoiceOver work as with any text field).
///
/// The caller owns the value: `onChange` receives what was typed and decides
/// what to keep (e.g. digits only, at most `length`). `isError` draws the
/// boxes in red, e.g. after a wrong code. Used by the Apple ID two-factor
/// step (`AppleIdSignInView`).
struct StackVerificationCodeField: View {

    let code: String
    let length: Int
    var isError = false
    var isDisabled = false
    let onChange: (String) -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        ZStack {
            TextField("", text: Binding(get: { code }, set: onChange))
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .focused($isFocused)
                .foregroundStyle(.clear)
                .tint(.clear)
                .accessibilityLabel(String(localized: "Verification code"))
                .accessibilityValue(code)
                .disabled(isDisabled)

            HStack(spacing: 8) {
                ForEach(0..<max(length, 1), id: \.self) { index in
                    buildBox(at: index)
                }
            }
            .accessibilityHidden(true)
            .allowsHitTesting(false)
        }
        .contentShape(Rectangle())
        .onTapGesture { isFocused = true }
        .onAppear { isFocused = true }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }

    private func buildBox(at index: Int) -> some View {
        let characters = Array(code)
        let digit = index < characters.count ? String(characters[index]) : ""
        let isCurrent = isFocused && index == min(characters.count, length - 1)
        return Text(digit)
            .font(.title2.monospacedDigit())
            .fontWeight(.semibold)
            .frame(width: 40, height: 50)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(borderColor(isCurrent: isCurrent), lineWidth: isCurrent || isError ? 2 : 1)
            )
    }

    private func borderColor(isCurrent: Bool) -> Color {
        if isError { return .red }
        return isCurrent ? .accentColor : Color(.separator)
    }
}

#Preview {
    Form {
        StackVerificationCodeField(code: "123", length: 6) { _ in }
        StackVerificationCodeField(code: "", length: 6, isError: true) { _ in }
    }
}
