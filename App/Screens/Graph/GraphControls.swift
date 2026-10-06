import SwiftUI

struct GraphControls: View {
    let maximumWeight: Int
    @Binding var filter: GraphFilter
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Toggle("Kişiler", isOn: $filter.people)
                Toggle("Konumlar", isOn: $filter.places)
                Toggle("Günler", isOn: $filter.days)
            }.toggleStyle(.button)
            HStack {
                Picker("Tarih aralığı", selection: $filter.period) {
                    Text("Son 30 gün").tag(GraphPeriod.month)
                    Text("Son 90 gün").tag(GraphPeriod.quarter)
                    Text("Son 365 gün").tag(GraphPeriod.year)
                    Text("Tümü").tag(GraphPeriod.all)
                }
                Stepper(value: $filter.minimumWeight, in: 1...max(maximumWeight, filter.minimumWeight)) {
                    Text("En az \(filter.minimumWeight) ortak gün")
                }
            }
            .font(.ink.meta)
            .foregroundStyle(Color.ink.secondaryText)
        }
        .padding(InkSpacing.margin)
    }
}
