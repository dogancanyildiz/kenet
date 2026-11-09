import SwiftUI

/// Byline sentence that elevates counts: formatted count phrases and glue.
struct InkSummaryLine: View {
    enum Part: Sendable {
        /// Conjunction / glue ("Bugün", "ve", "kaldı").
        case text(String)
        /// Caller-formatted count phrase (e.g. LocalizedStringResource for "2 olay").
        case count(LocalizedStringResource, symbol: String? = nil)
    }

    var parts: [Part]

    var body: some View {
        InkFlowLayout(spacing: 4, lineSpacing: 2) {
            ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                switch part {
                case .text(let text):
                    Text(verbatim: text)
                        .font(.ink.byline)
                        .foregroundStyle(Color.ink.secondaryText)
                case .count(let resource, let symbol):
                    HStack(spacing: 4) {
                        if let symbol {
                            Image(systemName: symbol)
                                .font(.ink.byline)
                                .foregroundStyle(Color.ink.text)
                                .accessibilityHidden(true)
                        }
                        Text(resource)
                            .font(.system(.title3, design: .default, weight: .semibold).monospacedDigit())
                            .foregroundStyle(Color.ink.text)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: Self.spokenParts(parts).joined(separator: " ")))
    }

    /// Spoken words for unit tests (glue + resolved count keys).
    nonisolated static func spokenParts(_ parts: [Part]) -> [String] {
        parts.map { part in
            switch part {
            case .text(let text): text
            case .count(let resource, _): String(localized: resource)
            }
        }
        .filter { !$0.isEmpty }
    }
}
