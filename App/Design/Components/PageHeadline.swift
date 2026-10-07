import SwiftUI

/// Page manşet: New York Semibold display title with an optional byline (jury condition 4).
struct PageHeadline: View {
    private enum Title {
        case verbatim(String)
        case key(LocalizedStringKey)
    }

    private let title: Title
    var byline: String? = nil

    init(title: String, byline: String? = nil) {
        self.title = .verbatim(title)
        self.byline = byline
    }

    init(_ title: LocalizedStringKey, byline: String? = nil) {
        self.title = .key(title)
        self.byline = byline
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            titleText
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

    @ViewBuilder private var titleText: some View {
        switch title {
        case .verbatim(let text):
            Text(verbatim: text)
        case .key(let key):
            Text(key)
        }
    }
}
