import SwiftCrossUI
import StackHomeCore

// Phase 4 · B1b-2 · T-C2 — shared building blocks for the three Windows widget
// views (US-007, design §2.5 / §2.8). The Windows counterpart of the iOS
// `HomeWidgetComponents.swift`: the card chrome, header row, loading/empty rows,
// the app row (36×36 gray placeholder icon + name/status/version/platform), and
// the placeholder icon itself.
//
// Card chrome is applied via a view modifier rather than a wrapper-with-closure
// view, matching the sibling pattern (WindowsProviderCardView /
// WindowsWidgetsEmptyStateView own their own chrome) and keeping clear of any
// `@ViewBuilder`-init capability question on SwiftCrossUI 0.7.

// MARK: - Card chrome

extension View {
    /// Wraps widget content in the standard widget card: 16px padding, ~8% gray
    /// fill, 1px border, radius 8, no drop shadow (design §2.4 widget card spec).
    /// Identical chrome to `WindowsWidgetsEmptyStateView` so every widget card
    /// matches.
    func windowsWidgetCard() -> some View {
        self
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color(white: 0.92).opacity(0.08))
            .cornerRadius(WindowsWidgetMetrics.cardRadius)
            .overlay {
                RoundedRectangle(cornerRadius: Double(WindowsWidgetMetrics.cardRadius))
                    .stroke(Color.gray.opacity(0.3), style: StrokeStyle(width: 1.0))
            }
    }
}

enum WindowsWidgetMetrics {
    /// Corner radius shared with the provider/empty-state cards (design §2.4).
    static let cardRadius = 8
    /// App-icon placeholder side length (design §2.5: 36×36 gray square).
    static let placeholderIconSize = 36.0
}

// MARK: - Header

/// The widget header row: a glyph (Unicode/emoji per §2.8) + bold title +
/// "(count)" secondary + trailing Spacer (design §2.5). The count is hidden when
/// zero, mirroring the iOS `HomeWidgetSectionHeader`.
struct WindowsWidgetHeaderView: View {
    let glyph: String
    let title: String
    let count: Int

    var body: some View {
        HStack(spacing: 6) {
            Text(glyph)
                .fontWeight(.bold)
            Text(title)
                .fontWeight(.semibold)
            if count > 0 {
                Text("(\(count))")
                    .foregroundColor(.gray)
            }
            Spacer()
        }
    }
}

// MARK: - Loading / empty rows

/// Single "Loading…" text row shown while a widget's `load()` is in flight
/// (US-007 AC-5, design §2.5: text, no shimmer; ProgressView treated as
/// uncertain → text fallback).
struct WindowsWidgetLoadingRow: View {
    var body: some View {
        HStack {
            Text("Loading…")
                .foregroundColor(.gray)
            Spacer()
        }
    }
}

/// Single secondary-color text row for a widget's empty state (design §2.5).
struct WindowsWidgetEmptyRow: View {
    let text: String

    var body: some View {
        HStack {
            Text(text)
                .foregroundColor(.gray)
            Spacer()
        }
    }
}

// MARK: - Placeholder app icon (D4 — no AsyncImage / image fetch)

/// A 36×36 gray rounded square standing in for the app icon. Windows v1 never
/// fetches/caches icons (D4), so this is a flat placeholder for every app/review
/// row.
struct WindowsWidgetPlaceholderIcon: View {
    var body: some View {
        Color.gray.opacity(0.2)
            .frame(
                width: WindowsWidgetMetrics.placeholderIconSize,
                height: WindowsWidgetMetrics.placeholderIconSize
            )
            .cornerRadius(8)
    }
}

// MARK: - App row (In Review / Awaiting Release)

/// A single app row: 36×36 gray placeholder icon + the app name (with an optional
/// trailing platform label), the App Store status, and the version. Mirrors the
/// iOS `HomeAppRowView`; all values come straight off the core `AppModel`.
struct WindowsWidgetAppRow: View {
    let app: AppModel
    /// Whether to show the platform label next to the name (In Review groups by
    /// platform; Awaiting Release does not).
    var showsPlatform: Bool = false

    private var platform: AppPlatform? {
        app.platform.flatMap { AppPlatform(rawValue: $0) }
    }

    var body: some View {
        HStack(spacing: 12) {
            WindowsWidgetPlaceholderIcon()

            VStack(spacing: 2) {
                HStack(spacing: 6) {
                    Text(app.name)
                        .fontWeight(.medium)
                    if showsPlatform, let platform {
                        Text(platform.displayName)
                            .foregroundColor(.gray)
                    }
                    Spacer()
                }

                if let state = app.appStoreState {
                    HStack(spacing: 6) {
                        Text(state.displayName)
                            .foregroundColor(.gray)
                        if let version = app.versionString {
                            Text("(\(version))")
                                .foregroundColor(.gray)
                        }
                        Spacer()
                    }
                }
            }

            Text(">")
                .foregroundColor(.gray)
        }
    }
}
