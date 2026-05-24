import SwiftUI

// MARK: - Row Model

struct CSVTesterRow: Identifiable, Hashable {
    let id = UUID()
    let firstName: String
    let lastName: String
    let email: String

    var displayName: String {
        let parts = [firstName, lastName].filter { !$0.isEmpty }
        return parts.isEmpty ? email : parts.joined(separator: " ")
    }
}

// MARK: - Parser

enum CSVTesterParser {

    /// Parses a CSV string in the format: name, lastName, email
    /// - Lines starting with a header (`email` keyword anywhere) are skipped.
    /// - Empty lines and lines without a valid email are skipped.
    static func parse(_ text: String) -> [CSVTesterRow] {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        var rows: [CSVTesterRow] = []
        for (index, rawLine) in normalized.components(separatedBy: "\n").enumerated() {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }

            let fields = splitFields(line).map { $0.trimmingCharacters(in: .whitespaces) }
            guard fields.count >= 3 else { continue }

            let firstName = fields[0]
            let lastName = fields[1]
            let email = fields[2]

            // Skip header row
            if index == 0, looksLikeHeader(firstName: firstName, lastName: lastName, email: email) {
                continue
            }

            guard isValidEmail(email) else { continue }
            rows.append(CSVTesterRow(firstName: firstName, lastName: lastName, email: email))
        }
        return rows
    }

    private static func splitFields(_ line: String) -> [String] {
        // Handles simple quoted fields: "value, with comma",unquoted,value
        var result: [String] = []
        var current = ""
        var inQuotes = false
        for char in line {
            if char == "\"" {
                inQuotes.toggle()
            } else if char == "," && !inQuotes {
                result.append(current)
                current = ""
            } else {
                current.append(char)
            }
        }
        result.append(current)
        return result
    }

    private static func looksLikeHeader(firstName: String, lastName: String, email: String) -> Bool {
        let lowered = [firstName, lastName, email].map { $0.lowercased() }
        return lowered.contains(where: { $0 == "email" || $0 == "e-mail" })
    }

    private static func isValidEmail(_ value: String) -> Bool {
        guard value.contains("@"), value.contains(".") else { return false }
        return value.range(of: "^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", options: .regularExpression) != nil
    }
}

// MARK: - Preview Sheet View

struct CSVTesterImportView: View {

    let rows: [CSVTesterRow]
    let existingEmails: Set<String>
    let isInviting: Bool
    let onContinue: ([CSVTesterRow]) -> Void
    let onCancel: () -> Void

    private func isDuplicate(_ row: CSVTesterRow) -> Bool {
        existingEmails.contains(row.email.lowercased())
    }

    private var importableRows: [CSVTesterRow] {
        rows.filter { !isDuplicate($0) }
    }

    var body: some View {
        Group {
            if rows.isEmpty {
                ContentUnavailableView {
                    Label(String(localized: "No Valid Rows"), systemImage: "doc.text.magnifyingglass")
                } description: {
                    Text("The selected file does not contain any valid rows (name, lastName, email).")
                }
            } else {
                buildList()
            }
        }
        .navigationTitle(String(localized: "Import Testers"))
        .navigationBarTitleDisplayMode(.inline)
        .disabled(isInviting)
        .toolbar { buildToolbar() }
        .overlay {
            if isInviting {
                ZStack {
                    Color.black.opacity(0.1)
                    ProgressView()
                        .scaleEffect(1.2)
                }
                .ignoresSafeArea()
            }
        }
    }

    @ViewBuilder
    private func buildList() -> some View {
        List {
            Section {
                ForEach(rows) { row in
                    buildRow(row)
                        .opacity(isDuplicate(row) ? 0.3 : 1.0)
                }
            } header: {
                HStack {
                    Text("Found \(rows.count) row(s)")
                    Spacer()
                    Text("\(importableRows.count) new")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } footer: {
                if importableRows.count < rows.count {
                    Text("Rows highlighted in gray are already in this group and will be skipped.")
                }
            }
        }
    }

    private func buildRow(_ row: CSVTesterRow) -> some View {
        HStack(spacing: 12) {
            Image(systemName: isDuplicate(row) ? "person.crop.circle.badge.checkmark" : "person.crop.circle")
                .font(.title3)
                .foregroundStyle(isDuplicate(row) ? Color.secondary : Color.blue)

            VStack(alignment: .leading, spacing: 2) {
                Text(row.displayName)
                    .font(.body)
                Text(row.email)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isDuplicate(row) {
                Text(String(localized: "Already in group"))
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.gray.opacity(0.12))
                    .clipShape(Capsule())
            }
        }
    }

    @ToolbarContentBuilder
    private func buildToolbar() -> some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button(String(localized: "Cancel")) { onCancel() }
        }
        ToolbarItem(placement: .confirmationAction) {
            if isInviting {
                ProgressView()
            } else {
                Button(String(localized: "Continue")) {
                    onContinue(importableRows)
                }
                .disabled(importableRows.isEmpty)
            }
        }
    }
}
