import SwiftUI

/// One step of an ordered explanation: `{①} {title / detail}` with optional
/// content under the text (e.g. a `StackExternalLink` to where it happens in
/// the code). Same numbered badge as the "How to" tutorials.
///
/// Used by "How Your Password Is Used".
struct StackNumberedStepRow<Accessory: View>: View {

    let number: Int
    let title: String
    var detail: String?
    @ViewBuilder let accessory: () -> Accessory

    @ScaledMetric(relativeTo: .subheadline) private var badgeSize: CGFloat = 24

    init(number: Int, title: String, detail: String? = nil, @ViewBuilder accessory: @escaping () -> Accessory) {
        self.number = number
        self.title = title
        self.detail = detail
        self.accessory = accessory
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(verbatim: "\(number)")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.white)
                .frame(width: badgeSize, height: badgeSize)
                .background(Color.accentColor, in: Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .fixedSize(horizontal: false, vertical: true)
                    if let detail {
                        Text(detail)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                // Step number, title and detail are read as one element;
                // the accessory (a link) stays its own.
                .accessibilityElement(children: .combine)
                .accessibilityLabel(Text(verbatim: "\(number). \(title)" + (detail.map { ". \($0)" } ?? "")))

                accessory()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 4)
    }
}

extension StackNumberedStepRow where Accessory == EmptyView {
    /// A step without accessory content.
    init(number: Int, title: String, detail: String? = nil) {
        self.init(number: number, title: title, detail: detail, accessory: { EmptyView() })
    }
}

#Preview {
    List {
        StackNumberedStepRow(number: 1, title: "You type it on this device", detail: "Only on this screen.")
        StackNumberedStepRow(number: 2, title: "Saved only if you turn it on") {
            Link(destination: ProjectLinks.applePasswordKeychainStore) {
                Text(verbatim: "ApplePasswordKeychainStore.swift")
            }
            .font(.subheadline)
        }
    }
}
