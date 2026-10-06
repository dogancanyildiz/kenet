import SwiftUI

/// Page manşet: New York Semibold display title with an optional byline (jury condition 4).
struct PageHeadline: View {
    let title: String
    var byline: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: title)
                .font(.ink.display)
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
