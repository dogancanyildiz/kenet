import SwiftUI

struct SummaryChangeBadge: View {
    let value: Double
    private var change: SummaryChange { SummaryChange(value: value) }
    var body: some View {
        Label(change.magnitude.formatted(.number.precision(.fractionLength(0...2))), systemImage: change.symbol)
            .font(.caption).foregroundStyle(.secondary)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityText)
            .accessibilityValue(Text(verbatim: change.magnitude.formatted()))
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
        HStack {
            Text(title)
            Spacer()
            Text(value.formatted()).monospacedDigit()
            SummaryChangeBadge(value: Double(change)).frame(minWidth: 48, alignment: .trailing)
        }
    }
}
