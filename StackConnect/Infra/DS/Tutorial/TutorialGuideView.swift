import SwiftUI

// MARK: - Models

/// A single step inside a ``TutorialBlock``.
///
/// `text` is the main line; `detail` is an optional secondary description
/// rendered below it (used by the API/JSON guides).
struct TutorialStep: Identifiable {
    let id = UUID()
    let text: String
    var detail: String? = nil
}

/// A logical group of steps inside a ``TutorialGuideView``.
///
/// Each block has an SF Symbol `icon`, a `title`, an ordered list of `steps`
/// and an optional share affordance in its header.
struct TutorialBlock: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let steps: [TutorialStep]
    var isShareable: Bool = true
}

// MARK: - View

/// Reusable, data-driven "How to" tutorial.
///
/// Renders its own `Section` containing a collapsible `DisclosureGroup`. Each
/// ``TutorialBlock`` is shown with an SF Symbol header, an optional `ShareLink`
/// and a list of numbered-circle steps. Drop it straight into a `Form`:
///
/// ```swift
/// TutorialGuideView(
///     label: String(localized: "How to find the UDID"),
///     systemImage: "questionmark.circle",
///     blocks: blocks,
///     caption: String(localized: "...")
/// )
/// ```
struct TutorialGuideView: View {

    let label: String
    let systemImage: String
    let blocks: [TutorialBlock]
    var caption: String? = nil

    var body: some View {
        // Single-block guides (API/JSON key) don't need a per-block header: the
        // DisclosureGroup label already states the title, so repeating it would
        // be redundant. Multi-block guides (UDID) keep headers to distinguish
        // each method.
        let showHeader = blocks.count > 1

        return Section {
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(blocks) { block in
                        buildBlock(block, showHeader: showHeader)
                    }

                    if let caption {
                        Text(caption)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.vertical, 8)
            } label: {
                Label(label, systemImage: systemImage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Builders

    @ViewBuilder
    private func buildBlock(_ block: TutorialBlock, showHeader: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if showHeader {
                HStack(spacing: 8) {
                    Image(systemName: block.icon)
                        .foregroundStyle(.blue)
                    Text(block.title)
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    Spacer()

                    if block.isShareable {
                        ShareLink(item: Self.makeShareText(for: block)) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.subheadline)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(String(localized: "Share \(block.title)"))
                    }
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(block.steps.enumerated()), id: \.element.id) { index, step in
                    buildStep(number: index + 1, step: step)
                }
            }
        }
    }

    private func buildStep(number: Int, step: TutorialStep) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(Color.accentColor)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(step.text)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .fixedSize(horizontal: false, vertical: true)

                if let detail = step.detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: - Share

    /// Builds the shareable plain-text representation of a block, incorporating
    /// the optional step detail when present.
    static func makeShareText(for block: TutorialBlock) -> String {
        var lines: [String] = [block.title, ""]
        for (index, step) in block.steps.enumerated() {
            if let detail = step.detail {
                lines.append("\(index + 1). \(step.text) — \(detail)")
            } else {
                lines.append("\(index + 1). \(step.text)")
            }
        }
        return lines.joined(separator: "\n")
    }
}
