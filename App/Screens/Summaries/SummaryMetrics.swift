import SwiftUI

struct SummaryChangeBadge: View {
    let value: Double
    private var change: SummaryChange { SummaryChange(value: value) }
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: change.symbol)
                .font(.caption.weight(.semibold))
                .accessibilityHidden(true)
            Text(verbatim: signedMagnitude)
                .font(.ink.meta)
                .monospacedDigit()
        }
        .foregroundStyle(Color.ink.secondaryText)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityValue(Text(verbatim: change.magnitude.formatted()))
    }

    private var signedMagnitude: String {
        let formatted = change.magnitude.formatted(.number.precision(.fractionLength(0...2)))
        if value > 0 { return "+" + formatted }
        if value < 0 { return "−" + formatted }
        return "=" + formatted
    }

    private var accessibilityText: Text {
        value > 0 ? Text("Artış") : value < 0 ? Text("Azalış") : Text("Değişim yok")
    }
}

struct SummaryMetric: View {
    let title: LocalizedStringKey
    let value: Int
    let change: Int
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                LargeNumberText(verbatim: value.formatted())
                Text(title)
                    .font(.ink.meta)
                    .foregroundStyle(Color.ink.secondaryText)
            }
            Spacer(minLength: 8)
            SummaryChangeBadge(value: Double(change))
                .frame(minWidth: 72, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
    }
}
