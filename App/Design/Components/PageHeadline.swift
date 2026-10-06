import SwiftUI

/// Page manşet: display title with an optional byline. Kept compact (jury condition 4).
struct PageHeadline: View {
    let title: String
    var byline: String? = nil
    /// Today uses a title-sized manşet so the first event stays on the first screen.
    var compact: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 1 : 2) {
            Text(verbatim: title)
                .font(compact ? Font.system(.title, design: .serif, weight: .semibold) : Font.ink.display)
                .foregroundStyle(.ink.text)
                .accessibilityAddTraits(.isHeader)
            if let byline, !byline.isEmpty {
                Text(verbatim: byline)
                    .font(.ink.byline)
                    .foregroundStyle(.ink.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
