import SwiftUI

/// Byline sentence that elevates counts: formatted count phrases and glue.
struct InkSummaryLine: View {
    enum Part: Sendable {
        /// Conjunction / glue ("Bugün", "ve", "kaldı").
        case text(String)
        /// Caller-formatted count phrase (e.g. LocalizedStringResource for "2 olay"), with
        /// optional punctuation glued to it (",", ".") so it never wraps or floats alone.
        case count(LocalizedStringResource, symbol: String? = nil, suffix: String = "")
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
                case .count(let resource, let symbol, let suffix):
                    HStack(spacing: 4) {
                        if let symbol {
                            Image(systemName: symbol)
                                .font(.ink.byline)
                                .foregroundStyle(Color.ink.text)
                                .accessibilityHidden(true)
                        }
                        HStack(spacing: 0) {
                            Text(resource)
                            if !suffix.isEmpty {
                                Text(verbatim: suffix)
                            }
                        }
                        .font(.system(.title3, design: .default, weight: .semibold).monospacedDigit())
                        .foregroundStyle(Color.ink.text)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: Self.spoken(parts)))
        // A sentence, not a control: without the trait the combined element is a bare "Other", and the
        // audit's hit region check took it for a control too small to tap (dev run 43004609707).
        .accessibilityAddTraits(.isStaticText)
    }

    /// Spoken words for unit tests (glue + resolved count keys with their glued suffix).
    nonisolated static func spokenParts(_ parts: [Part]) -> [String] {
        parts.map { part in
            switch part {
            case .text(let text): text
            case .count(let resource, _, let suffix): String(localized: resource) + suffix
            }
        }
        .filter { !$0.isEmpty }
    }

    /// The whole sentence as VoiceOver reads it: parts joined by single spaces.
    nonisolated static func spoken(_ parts: [Part]) -> String {
        spokenParts(parts).joined(separator: " ")
    }
}
