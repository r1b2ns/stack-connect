import SwiftCrossUI
import StackHomeCore

// T-W06 — A single row in the apps list displaying the app's icon, name,
// colored status badge, version string, a disclosure chevron, and an explicit
// Archive button. Tapping the row body navigates to app detail; the Archive
// button triggers the archive-confirmation flow.
//
// Per TC-069: Archive is an explicit button, NOT a swipe action (SwiftCrossUI
// has no swipe actions). Per AC-W01-1: rows show icon, name, colored status,
// status text, and version.
//
// The icon uses a text glyph fallback (SwiftCrossUI has no AsyncImage for
// remote icon URLs). The status is rendered via the T-W04 `WindowsStatusBadge`.

struct WindowsAppRow: View {
    let app: AppModel
    let onTap: () -> Void
    let onToggleFavorite: () -> Void
    let onArchive: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // App icon fallback glyph (no remote image loading in SwiftCrossUI)
            Text(iconGlyph)
                .font(.title3)
                .frame(width: 36, height: 36)
                .background(Color.blue.opacity(0.10))
                .cornerRadius(8)

            // App name + version
            VStack(alignment: .leading, spacing: 2) {
                Text(app.name)
                    .fontWeight(.medium)

                // Version string (if available)
                if let version = app.versionString, !version.isEmpty {
                    Text("v\(version)")
                        .foregroundColor(.gray)
                }
            }

            Spacer()

            // Colored status badge (T-W04 component, AC-W01-6/7/8)
            if let state = app.appStoreState {
                WindowsStatusBadge(state: state)
            }

            // Favorite toggle (AC-W03-1..3): star glyph toggles isFavorite.
            // Filled star when favorited, outline when not.
            Button(app.isFavorite ? "\u{2605}" : "\u{2606}") {
                onToggleFavorite()
            }
            .foregroundColor(app.isFavorite ? .yellow : .gray)

            // Explicit Archive button (TC-069 / AC-W04)
            Button("Archive") {
                onArchive()
            }
            .foregroundColor(.orange)

            // Disclosure chevron
            Text(">")
                .foregroundColor(.gray)
        }
        .padding(12)
        .background(Color(white: 0.97))
        .cornerRadius(8)
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.gray.opacity(0.3), style: StrokeStyle(width: 1.0))
        }
        .onTapGesture {
            onTap()
        }
    }

    // MARK: - Icon Glyph Fallback

    /// A graceful fallback when no remote icon is available. Uses the first
    /// letter of the app name (uppercased), or a generic app glyph.
    private var iconGlyph: String {
        if let first = app.name.first {
            return String(first).uppercased()
        }
        return "\u{25A0}" // filled square as generic app glyph
    }
}
