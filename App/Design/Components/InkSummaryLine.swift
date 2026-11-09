import SwiftUI

/// Byline sentence that elevates counts: numbers and their nouns in text/semibold, glue in secondary.
struct InkSummaryLine: View {
    enum Part: Equatable, Sendable {
        /// Conjunction / glue ("Bugün", "ve", "var.").
        case text(String)
        /// Count + noun, optionally with a leading SF Symbol and a glued suffix (",").
        case count(Int, String, symbol: String? = nil, suffix: String = "")
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
                case .count(let value, let noun, let symbol, let suffix):
                    HStack(spacing: 4) {
                        if let symbol {
                            Image(systemName: symbol)
                                .font(.ink.byline)
                                .foregroundStyle(Color.ink.text)
                                .accessibilityHidden(true)
                        }
                        Text(verbatim: "\(value) \(noun)\(suffix)")
                            .font(.system(.title3, design: .default, weight: .semibold).monospacedDigit())
                            .foregroundStyle(Color.ink.text)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: Self.spoken(parts)))
    }

    /// Joins parts with spaces, except a leading "." which glues to the previous piece.
    static func spoken(_ parts: [Part]) -> String {
        var result = ""
        for part in parts {
            let piece: String =
                switch part {
                case .text(let text): text
                case .count(let value, let noun, _, let suffix): "\(value) \(noun)\(suffix)"
                }
            guard !piece.isEmpty else { continue }
            if result.isEmpty {
                result = piece
            } else if piece == "." {
                result += piece
            } else {
                result += " " + piece
            }
        }
        return result
    }
}
