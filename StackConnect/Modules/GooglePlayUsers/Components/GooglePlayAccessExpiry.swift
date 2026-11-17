import SwiftUI

/// "Access Expiry — Never ›" (prototypes 17 and 21): opens
/// `GooglePlayAccessExpirySheet`. Shared by the user detail and the invite sheet.
struct GooglePlayAccessExpiryRow: View {

    let expiration: Date?
    var isEnabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text("Access Expiry")
                    .foregroundStyle(.primary)
                Spacer()
                Text(GooglePlayAccessExpiryRow.text(for: expiration))
                    .foregroundStyle(.secondary)
                if isEnabled {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }

    static func text(for expiration: Date?) -> String {
        expiration?.formatted(date: .abbreviated, time: .omitted)
            ?? String(localized: "Never", comment: "Google Play access expiry: the access doesn't expire.")
    }
}

/// Picks when a Google Play user's access ends, or never.
struct GooglePlayAccessExpirySheet: View {

    let initial: Date?
    let onDone: (Date?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var expires: Bool
    @State private var date: Date

    init(initial: Date?, onDone: @escaping (Date?) -> Void) {
        self.initial = initial
        self.onDone = onDone
        _expires = State(initialValue: initial != nil)
        _date = State(initialValue: initial ?? Calendar.current.date(byAdding: .month, value: 3, to: Date()) ?? Date())
    }

    private var tomorrow: Date {
        Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: Date())) ?? Date()
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle(String(localized: "Access Expires"), isOn: $expires.animation())
                    if expires {
                        DatePicker(
                            String(localized: "Expiry Date"),
                            selection: $date,
                            in: tomorrow...,
                            displayedComponents: .date
                        )
                        .datePickerStyle(.graphical)
                    }
                } footer: {
                    Text("On this day Google Play removes the user's access. An invitation that isn't accepted by then expires too.")
                }
            }
            .navigationTitle(String(localized: "Access Expiry"))
            .navigationBarTitleDisplayMode(.inline)
            .trackScreen(.googlePlayAccessExpiry)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    StackTrackedButton(String(localized: "Cancel"), button: .cancel, on: .googlePlayAccessExpiry) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    StackTrackedButton(String(localized: "Done"), button: .done, on: .googlePlayAccessExpiry) {
                        onDone(expires ? Calendar.current.startOfDay(for: date) : nil)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.large])
    }
}
