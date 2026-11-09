import SwiftUI

/// Byline sentence that elevates counts: numbers and their nouns in text/semibold, glue in secondary.
struct InkSummaryLine: View {
    enum Part: Equatable, Sendable {
        /// Conjunction / glue ("Bugün", "ve", "kaldı").
        case text(String)
        /// Count + noun, optionally with a leading SF Symbol.
        case count(Int, String, symbol: String? = nil)
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
                case .count(let value, let noun, let symbol):
                    HStack(spacing: 4) {
                        if let symbol {
                            Image(systemName: symbol)
                                .font(.ink.byline)
                                .foregroundStyle(Color.ink.text)
                                .accessibilityHidden(true)
                        }
                        Text(verbatim: "\(value) \(noun)")
                            .font(.system(.title3, design: .default, weight: .semibold).monospacedDigit())
                            .foregroundStyle(Color.ink.text)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: spoken))
    }

    private var spoken: String {
        parts.map { part in
            switch part {
            case .text(let text): text
            case .count(let value, let noun, _): "\(value) \(noun)"
            }
        }
        .filter { !$0.isEmpty }
        .joined(separator: " ")
    }
}
